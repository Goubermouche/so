#include "optimize/enumerate.cuh"
#include "util/device.cuh"

__constant__ EnumMeta c_meta[EnumMaxMeta];
__constant__ I64 c_imms[EnumImmPoolSize];

void enum_make_opcode_pool(EnumOpcodePool* pool, U32 ext_mask) {
	*pool = {};

	for(U32 i = 0; i < (U32)InstructionOpcode_Count; ++i) {
		InstructionInfo* s = &instruction_db_host.row[i];
		if(s->op == InstructionOpcode_Nop) { continue; }
		if(!(s->ext & ext_mask)) { continue; }
		pool->ops[pool->n++] = (InstructionOpcode)i;
	}
}

void enum_make_imm_pool(EnumImmPool* pool, Program* prog) {
	*pool = {};

	// base
	for(I64 v = -8; v <= 8; ++v) { pool->vals[pool->n++] = v; }

	// extra
	static I64 extra[] = {
		9,
		10,
		12,
		15,
		24,
		31,
		100,
		1000,
		16,
		32,
		63,
		64,
		0xFF,
		0xFFFF,
	};
	for(I64 v : extra) {
		if(pool->n >= EnumImmPoolSize) { break; }
		pool->vals[pool->n++] = v;
	}

	// program immediates
	if(prog) {
		for(U32 i = 0; i < prog->size; ++i) {
			Instruction* ins = &prog->instructions[i];
			InstructionInfo* info = &instruction_db_host.row[ins->op];
			for(U32 k = 0; k < 4; ++k) {
				if(info->operands[k] != InstructionOperandType_Imm) { continue; }
				I64 v = (I64)ins->operands[k].imm;
				B32 dup = false;
				for(U32 j = 0; j < pool->n; ++j) {
					if(pool->vals[j] == v) {
						dup = true;
						break;
					}
				}
				if(!dup && pool->n < EnumImmPoolSize) { pool->vals[pool->n++] = v; }
			}
		}
	}
}

void enum_make_meta_host(EnumOpcodePool* pool, EnumMeta* out, U32* out_n) {
	U32 n = 0;
	for(U32 i = 0; i < pool->n; ++i) {
		InstructionOpcode op = pool->ops[i];
		InstructionInfo* info = &instruction_db_host.row[op];

		EnumMeta m;
		m.op = (U16)op;
		m.commutative = (U8)info->commutative;
		m.dst_slot = info->dst_slot;
		m.src_slot = info->src_slot;
		m.src2_slot = info->src2_slot;
		m.imm_slot = -1;

		for(U32 k = 0; k < 4; ++k) {
			if(info->operands[k] == InstructionOperandType_Imm) {
				m.imm_slot = (I8)k;
				break;
			}
		}

		B32 has_rs1 = info->src_slot >= 0;
		B32 has_rs2 = info->src2_slot >= 0;
		B32 has_imm = m.imm_slot >= 0;

		if(has_rs1 && has_rs2) {
			m.shape = InstructionShape_RRR;
		} else if(has_rs1 && has_imm) {
			m.shape = InstructionShape_RRI;
		} else if(has_imm) {
			m.shape = InstructionShape_RI;
		} else if(has_rs1) {
			m.shape = InstructionShape_RR;
		} else {
			continue;
		}

		out[n++] = m;
	}
	*out_n = n;
}

__device__ __forceinline__ void
opt_build_inst(EnumMeta* m, U32 rd, U32 rs1, U32 rs2_or_imm_idx, B32 is_imm, Instruction* out) {
	Instruction in;
	in.op = (InstructionOpcode)m->op;
#pragma unroll
	for(U32 k = 0; k < 4; ++k) { in.operands[k].imm = 0; }

	in.operands[m->dst_slot].reg = (Reg)rd;
	if(m->src_slot >= 0) { in.operands[m->src_slot].reg = (Reg)rs1; }
	if(!is_imm && m->src2_slot >= 0) { in.operands[m->src2_slot].reg = (Reg)rs2_or_imm_idx; }
	if(is_imm && m->imm_slot >= 0) { in.operands[m->imm_slot].imm = (U64)c_imms[rs2_or_imm_idx]; }

	*out = in;
}

__device__ __forceinline__ U64
pack_emit_tuple(U32 parent_local_id, U32 op_idx, U32 rd, U32 rs1, U32 rs2_or_imm_idx, B32 is_imm) {
	// 64-bit packed encoding consumed
	// bits:
	// - 0-31  parent_local_id
	// - 32-39 op_idx
	// - 40-44 rd
	// - 45-49 rs1
	// - 50-57 rs2_or_imm_idx
	// - 58    is_imm
	U64 t = (U64)parent_local_id & 0xFFFFFFFFull;
	t |= ((U64)op_idx & 0xFFull) << 32;
	t |= ((U64)rd & 0x1Full) << 40;
	t |= ((U64)rs1 & 0x1Full) << 45;
	t |= ((U64)rs2_or_imm_idx & 0xFFull) << 50;
	t |= ((U64)(is_imm ? 1u : 0u)) << 58;
	return t;
}

template<B32 EMIT, B32 LAST>
__device__ __forceinline__ U32 opt_try_one(
	EnumLayer* L,
	EnumStateHeader* src_hdr,
	EnumStateCode* src_code,
	EnumMeta* m,
	U32 op_idx,
	U32 rd,
	U32 rs1,
	U32 rs2_or_imm_idx,
	B32 is_imm,
	B32 rd_is_new_scratch,
	U32 parent_local_id,
	EnumStateHeader* dst_hdr,
	EnumStateCode* dst_code,
	U64* dst_tuples,
	U64 write_base,
	U32* write_local,
	U64 cap_states,
	U64 cap_cands
) {
	U64 new_demanded = src_hdr->demanded & ~(1ULL << rd);
	if(m->src_slot >= 0) {
		U32 r = rs1;
		if(r != 0 && !(L->live_in_mask & (1ULL << r))) { new_demanded |= 1ULL << r; }
	}
	if(!is_imm && m->src2_slot >= 0) {
		U32 r = rs2_or_imm_idx;
		if(r != 0 && !(L->live_in_mask & (1ULL << r))) { new_demanded |= 1ULL << r; }
	}

	U64 new_used_scratch = src_hdr->used_scratch;
	if(rd_is_new_scratch) { new_used_scratch |= 1ULL << rd; }

	if constexpr(LAST) {
		if((new_demanded & ~L->live_in_mask) != 0) { return 0; }
	} else {
		if(new_demanded == 0) { return 0; }
	}

	if constexpr(EMIT) {
		U64 slot = write_base + (U64)(*write_local);
		++(*write_local);
		if constexpr(LAST) {
			if(slot < cap_cands) {
				dst_tuples[slot] =
					pack_emit_tuple(parent_local_id, op_idx, rd, rs1, rs2_or_imm_idx, is_imm);
			}
		} else {
			if(slot < cap_states) {
				EnumStateHeader nh;
				nh.demanded = new_demanded;
				nh.used_scratch = new_used_scratch;
				nh.idx = src_hdr->idx - 1;
				nh._pad = 0;
				dst_hdr[slot] = nh;
				// copy parent code + write the new instruction at slot src->idx
				EnumStateCode nc;
#pragma unroll
				for(U32 k = 0; k < MaxProgramLen; ++k) { nc.code[k] = src_code->code[k]; }
				opt_build_inst(m, rd, rs1, rs2_or_imm_idx, is_imm, &nc.code[src_hdr->idx]);
				dst_code[slot] = nc;
			}
		}
	}

	return 1;
}

// expand one frontier node
template<B32 EMIT, B32 LAST>
__device__ U32 opt_expand_one(
	EnumLayer* L,
	EnumStateHeader* src_hdr,
	EnumStateCode* src_code,
	U32 parent_local_id,
	EnumStateHeader* dst_hdr,
	EnumStateCode* dst_code,
	U64* dst_tuples,
	U64 write_base,
	U64 cap_states,
	U64 cap_cands
) {
	U64 demanded = src_hdr->demanded;
	if(demanded == 0) { return 0; }
	U64 src_avail = L->src_avail;
	U64 used_scratch = src_hdr->used_scratch;
	U64 unused_scratch = L->scratch_mask & ~used_scratch;
	U64 next_scratch_bit = 0;
	if(unused_scratch != 0) {
		next_scratch_bit = unused_scratch & (~unused_scratch + 1ULL); // isolate lowest
	}
	U64 low_regs = 0x1EULL; // 1 - 4
	U64 valid_rd_pool = L->preserved_mask | used_scratch | next_scratch_bit | low_regs;
	U64 dst_avail = demanded & valid_rd_pool & ~1ULL; // never write x0

	if(dst_avail == 0) { return 0; }

	U32 n_meta = L->n_meta;
	U32 n_imms = L->n_imms;

	U32 local_count = 0;
	U32 write_local = 0;

	for(U32 oi = 0; oi < n_meta; ++oi) {
		EnumMeta m = c_meta[oi];

		// iterate dst registers
		U64 dst_iter = dst_avail;
		while(dst_iter) {
			U32 rd = (U32)__ffsll((long long)dst_iter) - 1;
			U64 rd_bit = dst_iter & (~dst_iter + 1ULL);
			dst_iter &= dst_iter - 1;
			B32 rd_is_new_scratch = (rd_bit == next_scratch_bit) && (next_scratch_bit != 0);

			switch(m.shape) {
				case InstructionShape_RRR: {
					U64 a = src_avail;
					while(a) {
						U32 rs1 = (U32)__ffsll((long long)a) - 1;
						a &= a - 1;
						U64 b = m.commutative ? (src_avail & ~((1ULL << rs1) - 1ULL)) : src_avail;
						while(b) {
							U32 rs2 = (U32)__ffsll((long long)b) - 1;
							b &= b - 1;
							local_count += opt_try_one<EMIT, LAST>(
								L,
								src_hdr,
								src_code,
								&m,
								oi,
								rd,
								rs1,
								rs2,
								false,
								rd_is_new_scratch,
								parent_local_id,
								dst_hdr,
								dst_code,
								dst_tuples,
								write_base,
								&write_local,
								cap_states,
								cap_cands
							);
						}
					}
					break;
				}
				case InstructionShape_RRI: {
					U64 a = src_avail;
					while(a) {
						U32 rs1 = (U32)__ffsll((long long)a) - 1;
						a &= a - 1;
						for(U32 ii = 0; ii < n_imms; ++ii) {
							local_count += opt_try_one<EMIT, LAST>(
								L,
								src_hdr,
								src_code,
								&m,
								oi,
								rd,
								rs1,
								ii,
								true,
								rd_is_new_scratch,
								parent_local_id,
								dst_hdr,
								dst_code,
								dst_tuples,
								write_base,
								&write_local,
								cap_states,
								cap_cands
							);
						}
					}
					break;
				}
				case InstructionShape_RI: {
					for(U32 ii = 0; ii < n_imms; ++ii) {
						local_count += opt_try_one<EMIT, LAST>(
							L,
							src_hdr,
							src_code,
							&m,
							oi,
							rd,
							0u,
							ii,
							true,
							rd_is_new_scratch,
							parent_local_id,
							dst_hdr,
							dst_code,
							dst_tuples,
							write_base,
							&write_local,
							cap_states,
							cap_cands
						);
					}
					break;
				}
				case InstructionShape_RR: {
					U64 a = src_avail;
					while(a) {
						U32 rs1 = (U32)__ffsll((long long)a) - 1;
						a &= a - 1;
						local_count += opt_try_one<EMIT, LAST>(
							L,
							src_hdr,
							src_code,
							&m,
							oi,
							rd,
							rs1,
							0u,
							false,
							rd_is_new_scratch,
							parent_local_id,
							dst_hdr,
							dst_code,
							dst_tuples,
							write_base,
							&write_local,
							cap_states,
							cap_cands
						);
					}
					break;
				}
			}
		}
	}

	return local_count;
}

template<B32 LAST>
__global__ void opt_count_kernel(
	EnumStateHeader* __restrict__ src_hdr_front, U32 n_src, EnumLayer e, U32* __restrict__ d_counts
) {
	U32 tid = blockIdx.x * blockDim.x + threadIdx.x;
	if(tid >= n_src) { return; }

	EnumStateHeader src_hdr = src_hdr_front[tid];
	U32 c = opt_expand_one<false, LAST>(&e, &src_hdr, 0, 0, 0, 0, 0, 0, 0, 0);
	d_counts[tid] = c;
}

__global__ void opt_emit_kernel_upper(
	EnumStateHeader* __restrict__ src_hdr_front,
	EnumStateCode* __restrict__ src_code_front,
	U32 n_src,
	U64* __restrict__ d_offsets,
	U64 base_adjust,
	EnumLayer e,
	EnumStateHeader* __restrict__ dst_hdr,
	EnumStateCode* __restrict__ dst_code,
	U64 cap_states
) {
	U32 tid = blockIdx.x * blockDim.x + threadIdx.x;
	if(tid >= n_src) { return; }

	EnumStateHeader src_hdr = src_hdr_front[tid];
	EnumStateCode src_code = src_code_front[tid];
	U64 base = d_offsets[tid] - base_adjust;
	opt_expand_one<true, false>(
		&e, &src_hdr, &src_code, tid, dst_hdr, dst_code, 0, base, cap_states, 0
	);
}

__global__ void opt_emit_tuples_kernel(
	EnumStateHeader* __restrict__ src_hdr_front,
	U32 n_src,
	U64* __restrict__ d_offsets,
	U64 base_adjust,
	EnumLayer e,
	U64* __restrict__ dst_tuples,
	U64 cap_cands
) {
	U32 tid = blockIdx.x * blockDim.x + threadIdx.x;
	if(tid >= n_src) { return; }

	EnumStateHeader src_hdr = src_hdr_front[tid];
	U64 base = d_offsets[tid] - base_adjust;
	opt_expand_one<true, true>(&e, &src_hdr, 0, tid, 0, 0, dst_tuples, base, 0, cap_cands);
}

I32 enum_make(Enum* e, U64 batch_size) {
	*e = {};
	e->n_meta = 0;
	e->n_imms_cap = EnumImmPoolSize;
	e->n_imms = 0;
	U64 capacity = Max(1024, batch_size);

	{
		U64 free_mem = 0;
		U64 total_mem = 0;
		cudaMemGetInfo(&free_mem, &total_mem);
		(void)total_mem;
		U64 reserved = 128ull * MB(1);
		U64 usable = free_mem > reserved ? (free_mem - reserved) : 0;
		U64 state_mem = 2ull * (sizeof(EnumStateHeader) + sizeof(EnumStateCode));
		U64 meta_mem = sizeof(U64) + sizeof(U32) + sizeof(U64);
		U64 per_slot = state_mem + meta_mem;
		U64 vram_capacity = usable / per_slot;
		if(vram_capacity < capacity) { capacity = vram_capacity; }
	}

	e->capacity = capacity;
	dmalloc(&e->d_front_a_hdr, capacity * sizeof(EnumStateHeader));
	dmalloc(&e->d_front_a_code, capacity * sizeof(EnumStateCode));
	dmalloc(&e->d_front_b_hdr, capacity * sizeof(EnumStateHeader));
	dmalloc(&e->d_front_b_code, capacity * sizeof(EnumStateCode));
	dmalloc(&e->d_counts, capacity * sizeof(U32));
	dmalloc(&e->d_offsets, capacity * sizeof(U64));
	dmalloc(&e->d_tuples, capacity * sizeof(U64));
	e->scan_tmp_bytes = 0;
	device_exclusive_sum(0, &e->scan_tmp_bytes, (U32*)e->d_counts, (U64*)e->d_offsets, (I32)capacity);
	dmalloc(&e->d_scan_tmp, e->scan_tmp_bytes);

	return 0;
}

void enum_free(Enum* e) {
	if(e->d_scan_tmp) { cudaFree(e->d_scan_tmp); }
	if(e->d_tuples) { cudaFree(e->d_tuples); }
	if(e->d_offsets) { cudaFree(e->d_offsets); }
	if(e->d_counts) { cudaFree(e->d_counts); }
	if(e->d_front_b_code) { cudaFree(e->d_front_b_code); }
	if(e->d_front_b_hdr) { cudaFree(e->d_front_b_hdr); }
	if(e->d_front_a_code) { cudaFree(e->d_front_a_code); }
	if(e->d_front_a_hdr) { cudaFree(e->d_front_a_hdr); }
	*e = {};
}

void enum_run(Enum* e, EnumOptions* opt) {
	e->out_n_cands = 0;
	e->out_parent_base = 0;
	e->out_n_parents_chunk = 0;
	e->last_layer_ready = false;
	e->d_last_front_hdr = 0;
	e->d_last_front_code = 0;
	e->last_layer_n_front = 0;
	e->last_layer_cursor = 0;
	e->last_layer_cap = 0;
	if(opt->cap == 0 || opt->prog_len == 0) { return; }

	// meta host
	EnumMeta h_meta[InstructionOpcode_Count];
	U32 n_meta = 0;
	enum_make_meta_host(opt->pool, h_meta, &n_meta);
	if(n_meta == 0) { return; }
	if(n_meta > EnumMaxMeta) {
		fprintf(stderr, "error: enum n_meta (%u) > EnumMaxMeta (%u)\n", n_meta, (U32)EnumMaxMeta);
		return;
	}

	U64 live_in = opt->live_in_mask & ~1ULL;
	U64 preserved = live_in | opt->live_out_mask;

	cudaMemcpyToSymbol(c_meta, h_meta, n_meta * sizeof(EnumMeta));
	cudaMemcpyToSymbol(c_imms, opt->imms->vals, opt->imms->n * sizeof(I64));
	e->n_meta = n_meta;
	e->n_imms = opt->imms->n;

	U64 capacity = e->capacity < opt->cap ? e->capacity : opt->cap;

	EnumStateHeader* d_hdr_a = (EnumStateHeader*)e->d_front_a_hdr;
	EnumStateCode* d_code_a = (EnumStateCode*)e->d_front_a_code;
	EnumStateHeader* d_hdr_b = (EnumStateHeader*)e->d_front_b_hdr;
	EnumStateCode* d_code_b = (EnumStateCode*)e->d_front_b_code;
	U32* d_counts = (U32*)e->d_counts;
	U64* d_offsets = (U64*)e->d_offsets;
	void* d_scan_tmp = e->d_scan_tmp;
	U64 scan_tmp_bytes = e->scan_tmp_bytes;

	// init root
	EnumStateHeader h_root_hdr;
	h_root_hdr.demanded = opt->live_out_mask;
	h_root_hdr.used_scratch = 0;
	h_root_hdr.idx = (I32)opt->prog_len - 1;
	h_root_hdr._pad = 0;
	EnumStateCode h_root_code;
	for(U32 k = 0; k < MaxProgramLen; ++k) {
		h_root_code.code[k] = {};
		h_root_code.code[k].op = InstructionOpcode_Nop;
	}
	htod_memcpy(d_hdr_a, &h_root_hdr, sizeof(EnumStateHeader));
	htod_memcpy(d_code_a, &h_root_code, sizeof(EnumStateCode));
	U64 n_front = 1;
	U64 scratch_mask = 0;

	{
		U32 hi = opt->max_scratch < 32 ? opt->max_scratch : 32;
		for(U32 r = 5; r < hi; ++r) {
			U64 bit = 1ULL << r;
			if(!(preserved & bit)) { scratch_mask |= bit; }
		}
	}

	for(I32 layer = (I32)opt->prog_len - 1; layer >= 0; --layer) {
		if(n_front == 0) { break; }
		U64 src_avail;
		if(layer == 0) {
			src_avail = live_in | 1ULL;
		} else {
			src_avail = live_in | 1ULL | scratch_mask | opt->live_out_mask;
		}

		EnumLayer lctx;
		lctx.n_meta = n_meta;
		lctx.n_imms = opt->imms->n;
		lctx.live_in_mask = live_in;
		lctx.live_out_mask = opt->live_out_mask;
		lctx.preserved_mask = preserved;
		lctx.src_avail = src_avail;
		lctx.scratch_mask = scratch_mask;
		lctx.max_scratch = opt->max_scratch;
		lctx.is_last_layer = (layer == 0);

		if(lctx.is_last_layer) {
			if(n_front > 0) {
				U32 threads_c = 256;
				U32 blocks_c = (U32)((n_front + threads_c - 1) / threads_c);
				opt_count_kernel<true><<<blocks_c, threads_c>>>(d_hdr_a, (U32)n_front, lctx, d_counts);
				check_cuda(cudaGetLastError(), "enum count kernel (last layer)");
				device_exclusive_sum(d_scan_tmp, &scan_tmp_bytes, d_counts, d_offsets, (I32)n_front);
			}

			e->last_layer_ready = true;
			e->d_last_front_hdr = d_hdr_a;
			e->d_last_front_code = d_code_a;
			e->last_layer_n_front = n_front;
			e->last_layer_cursor = 0;
			e->last_layer_cap = capacity;
			e->last_layer_ctx = lctx;
			break;
		}

		U32 threads = 256;
		U32 blocks = (U32)((n_front + threads - 1) / threads);

		// count (upper layer)
		opt_count_kernel<false><<<blocks, threads>>>(d_hdr_a, (U32)n_front, lctx, d_counts);
		check_cuda(cudaGetLastError(), "enum count kernel");
		device_exclusive_sum(d_scan_tmp, &scan_tmp_bytes, d_counts, d_offsets, (I32)n_front);

		// copyback
		U64 last_off = 0;
		U32 last_cnt = 0;
		dtoh_memcpy(&last_off, d_offsets + (n_front - 1), sizeof(U64));
		dtoh_memcpy(&last_cnt, d_counts + (n_front - 1), sizeof(U32));
		U64 total = last_off + (U64)last_cnt;

		if(total > 0) {
			U64 cap_states = capacity;

			opt_emit_kernel_upper<<<blocks, threads>>>(
				d_hdr_a, d_code_a, (U32)n_front, d_offsets, 0, lctx, d_hdr_b, d_code_b, cap_states
			);
			check_cuda(cudaGetLastError(), "enum emit upper kernel");
		}

		n_front = total < capacity ? total : capacity;
		EnumStateHeader* th = d_hdr_a;
		d_hdr_a = d_hdr_b;
		d_hdr_b = th;
		EnumStateCode* tc = d_code_a;
		d_code_a = d_code_b;
		d_code_b = tc;
	}
}

U64 enum_find_chunk_fit(U64* d_offsets, U64 cursor, U64 n_front, U64 total, U64 cap) {
	if(cursor >= n_front) { return 0; }

	// read offsets[cursor] (= base for the chunk)
	U64 base_off = 0;
	if(cursor > 0) { dtoh_memcpy(&base_off, d_offsets + cursor, sizeof(U64)); }

	U64 tail_total = total - base_off;
	U64 remaining = n_front - cursor;
	if(tail_total <= cap) { return remaining; }

	U64 lo = 0;
	U64 hi = remaining;
	while(lo + 1 < hi) {
		U64 mid = lo + (hi - lo) / 2;
		U64 off = 0;
		U64 absolute_idx = cursor + mid;
		if(absolute_idx < n_front) {
			dtoh_memcpy(&off, d_offsets + absolute_idx, sizeof(U64));
		} else {
			off = total;
		}
		if(off - base_off <= cap) {
			lo = mid;
		} else {
			hi = mid;
		}
	}
	return lo;
}

U64 enum_emit_batch(Enum* e) {
	e->out_n_cands = 0;
	e->out_parent_base = 0;
	e->out_n_parents_chunk = 0;

	if(!e->last_layer_ready) { return 0; }
	if(e->last_layer_cursor >= e->last_layer_n_front) { return 0; }

	U32* d_counts = (U32*)e->d_counts;
	U64* d_offsets = (U64*)e->d_offsets;
	U64 cap = e->last_layer_cap;
	EnumLayer lctx = e->last_layer_ctx;
	U64 cursor = e->last_layer_cursor;
	U64 n_front = e->last_layer_n_front;

	U64 last_off = 0;
	U32 last_cnt = 0;
	dtoh_memcpy(&last_off, d_offsets + (n_front - 1), sizeof(U64));
	dtoh_memcpy(&last_cnt, d_counts + (n_front - 1), sizeof(U32));
	U64 total = last_off + (U64)last_cnt;

	U64 k = enum_find_chunk_fit(d_offsets, cursor, n_front, total, cap);
	B32 forced_truncate = false;
	if(k == 0) {
		k = 1;
		forced_truncate = true;
	}

	// determine how many candidates the chunk will emit
	U64 base_off = 0;
	if(cursor > 0) { dtoh_memcpy(&base_off, d_offsets + cursor, sizeof(U64)); }
	U64 end_off = total;
	if(cursor + k < n_front) { dtoh_memcpy(&end_off, d_offsets + (cursor + k), sizeof(U64)); }
	U64 emitted = end_off - base_off;
	if(forced_truncate && emitted > cap) { emitted = cap; }

	if(emitted > 0) {
		U32 threads = 256;
		U64* d_tuples = (U64*)e->d_tuples;
		EnumStateHeader* d_hdr = (EnumStateHeader*)e->d_last_front_hdr;

		// emit packed tuples per cand
		U32 emit_blocks = (U32)((k + threads - 1) / threads);
		opt_emit_tuples_kernel<<<emit_blocks, threads>>>(
			d_hdr + cursor, (U32)k, d_offsets + cursor, base_off, lctx, d_tuples, cap
		);
		check_cuda(cudaGetLastError(), "enum emit tuples kernel");
		check_cuda(cudaDeviceSynchronize(), "enum emit sync");
	}

	e->last_layer_cursor += k;
	e->out_n_cands = emitted;
	e->out_parent_base = cursor;
	e->out_n_parents_chunk = k;
	return emitted;
}
