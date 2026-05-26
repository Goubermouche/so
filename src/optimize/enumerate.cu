#include "optimize/enumerate.cuh"
#include "util/device.cuh"

void enum_make_opcode_pool(EnumOpcodePool* pool, U32 ext_mask) {
	*pool = {};

	for(U32 i = 0; i < (U32)InstructionOpcode_Count; ++i) {
		const InstructionInfo& s = instruction_db_host.row[i];
		if(s.op == InstructionOpcode_Nop) { continue; }
		if(!(s.ext & ext_mask)) { continue; }
		pool->ops[pool->n++] = (InstructionOpcode)i;
	}
}

void enum_make_imm_pool(EnumImmPool* pool, const Program* prog) {
	*pool = {};

	// base
	for(I64 v = -8; v <= 8; ++v) { pool->vals[pool->n++] = v; }

	// extra
	const I64 extra[] = {
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
			const Instruction& ins = prog->instructions[i];
			const InstructionInfo* info = &instruction_db_host.row[ins.op];
			for(U32 k = 0; k < 4; ++k) {
				if(info->operands[k] != InstructionOperandType_Imm) { continue; }
				const I64 v = (I64)ins.operands[k].imm;
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

void enum_make_meta_host(const EnumOpcodePool* pool, EnumMeta* out, U32* out_n) {
	U32 n = 0;
	for(U32 i = 0; i < pool->n; ++i) {
		const InstructionOpcode op = pool->ops[i];
		const InstructionInfo& info = instruction_db_host.row[op];

		EnumMeta m;
		m.op = (U16)op;
		m.commutative = (U8)info.commutative;
		m.dst_slot = info.dst_slot;
		m.src_slot = info.src_slot;
		m.src2_slot = info.src2_slot;
		m.imm_slot = -1;

		for(U32 k = 0; k < 4; ++k) {
			if(info.operands[k] == InstructionOperandType_Imm) {
				m.imm_slot = (I8)k;
				break;
			}
		}

		const B32 has_rs1 = info.src_slot >= 0;
		const B32 has_rs2 = info.src2_slot >= 0;
		const B32 has_imm = m.imm_slot >= 0;

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

__device__ __forceinline__ void opt_build_inst(
	const EnumMeta* m,
	U32 rd,
	U32 rs1,
	U32 rs2_or_imm_idx,
	B32 is_imm,
	const I64* imms,
	Instruction* out
) {
	Instruction in;
	in.op = (InstructionOpcode)m->op;
#pragma unroll
	for(U32 k = 0; k < 4; ++k) { in.operands[k].imm = 0; }

	in.operands[m->dst_slot].reg = (Reg)rd;
	if(m->src_slot >= 0) { in.operands[m->src_slot].reg = (Reg)rs1; }
	if(!is_imm && m->src2_slot >= 0) { in.operands[m->src2_slot].reg = (Reg)rs2_or_imm_idx; }
	if(is_imm && m->imm_slot >= 0) { in.operands[m->imm_slot].imm = (U64)imms[rs2_or_imm_idx]; }

	*out = in;
}

__device__ __forceinline__ U64
pack_emit_tuple(U32 parent_local_id, U32 op_idx, U32 rd, U32 rs1, U32 rs2_or_imm_idx, B32 is_imm) {
	// 64-bit packed encoding consumed by opt_build_from_tuples_kernel
	// see bitfield layout in the comment above opt_try_one
	U64 t = (U64)parent_local_id & 0xFFFFFFFFull;
	t |= ((U64)op_idx & 0xFFull) << 32;
	t |= ((U64)rd & 0x1Full) << 40;
	t |= ((U64)rs1 & 0x1Full) << 45;
	t |= ((U64)rs2_or_imm_idx & 0xFFull) << 50;
	t |= ((U64)(is_imm ? 1u : 0u)) << 58;
	return t;
}

// packed-tuple bitfield layout (64 bits):
// - bits  0-31: parent_local_id (index into the chunk's src_front[])
// - bits 32-39: op_idx          (index into meta[])
// - bits 40-44: rd              (5 bits, RISC-V register 0..31)
// - bits 45-49: rs1             (5 bits)
// - bits 50-57: rs2_or_imm_idx  (8 bits; reg index for RRR, imm pool index for RRI/RI)
// - bit  58:    is_imm
template<B32 EMIT>
__device__ __forceinline__ U32 opt_try_one(
	const EnumLayer* L,
	const EnumState* src,
	const EnumMeta* m,
	U32 op_idx,
	U32 rd,
	U32 rs1,
	U32 rs2_or_imm_idx,
	B32 is_imm,
	B32 rd_is_new_scratch,
	U32 parent_local_id,
	EnumState* dst_states,
	Instruction* dst_cands_soa,
	U64 stride,
	U64* dst_tuples,
	U64 write_base,
	U32* write_local,
	U64 cap_states,
	U64 cap_cands
) {
	U64 new_demanded = src->demanded & ~(1ULL << rd);
	if(m->src_slot >= 0) {
		const U32 r = rs1;
		if(r != 0 && !(L->live_in_mask & (1ULL << r))) { new_demanded |= 1ULL << r; }
	}
	if(!is_imm && m->src2_slot >= 0) {
		const U32 r = rs2_or_imm_idx;
		if(r != 0 && !(L->live_in_mask & (1ULL << r))) { new_demanded |= 1ULL << r; }
	}

	U64 new_used_scratch = src->used_scratch;
	if(rd_is_new_scratch) { new_used_scratch |= 1ULL << rd; }

	if(L->is_last_layer) {
		if((new_demanded & ~L->live_in_mask) != 0) { return 0; }
	} else {
		if(new_demanded == 0) { return 0; }
	}

	if constexpr(EMIT) {
		const U64 slot = write_base + (U64)(*write_local);
		++(*write_local);
		if(L->is_last_layer) {
			// phase-1 last-layer emit: write a single 64-bit tuple referencing the parent and the
			// (op, rd, rs1, rs2/imm) chosen for slot 0. the phase-2 kernel (opt_build_from_tuples_kernel)
			// then reads this tuple plus the parent's EnumState and writes the full slot-major SoA
			// Instruction[MaxProgramLen] entry for this cand
			if(slot < cap_cands) {
				dst_tuples[slot] =
					pack_emit_tuple(parent_local_id, op_idx, rd, rs1, rs2_or_imm_idx, is_imm);
			}
		} else {
			if(slot < cap_states) {
				EnumState ns;
#pragma unroll
				for(U32 k = 0; k < MaxProgramLen; ++k) { ns.code[k] = src->code[k]; }
				opt_build_inst(m, rd, rs1, rs2_or_imm_idx, is_imm, L->imms, &ns.code[src->idx]);
				ns.demanded = new_demanded;
				ns.used_scratch = new_used_scratch;
				ns.idx = src->idx - 1;
				ns._pad = 0;
				dst_states[slot] = ns;
			}
		}
	}

	return 1;
}

// expand one frontier node
template<B32 EMIT>
__device__ U32 opt_expand_one(
	const EnumLayer* L,
	const EnumState* src,
	U32 parent_local_id,
	EnumState* dst_states,
	Instruction* dst_cands_soa,
	U64 stride,
	U64* dst_tuples,
	U64 write_base,
	U64 cap_states,
	U64 cap_cands
) {
	if(src->demanded == 0) { return 0; }
	const U64 src_avail = L->src_avail;
	const U64 unused_scratch = L->scratch_mask & ~src->used_scratch;
	U64 next_scratch_bit = 0;
	if(unused_scratch != 0) {
		next_scratch_bit = unused_scratch & (~unused_scratch + 1ULL); // isolate lowest
	}
	const U64 low_regs = 0x1EULL; // 1 - 4
	const U64 valid_rd_pool = L->preserved_mask | src->used_scratch | next_scratch_bit | low_regs;
	const U64 dst_avail = src->demanded & valid_rd_pool & ~1ULL; // never write x0

	if(dst_avail == 0) { return 0; }

	U32 local_count = 0;
	U32 write_local = 0;

	for(U32 oi = 0; oi < L->n_meta; ++oi) {
		const EnumMeta m = L->meta[oi];

		// iterate dst registers
		U64 dst_iter = dst_avail;
		while(dst_iter) {
			const U32 rd = (U32)__ffsll((long long)dst_iter) - 1;
			const U64 rd_bit = dst_iter & (~dst_iter + 1ULL);
			dst_iter &= dst_iter - 1;
			const B32 rd_is_new_scratch = (rd_bit == next_scratch_bit) && (next_scratch_bit != 0);

			switch(m.shape) {
				case InstructionShape_RRR: {
					U64 a = src_avail;
					while(a) {
						const U32 rs1 = (U32)__ffsll((long long)a) - 1;
						a &= a - 1;
						U64 b = m.commutative ? (src_avail & ~((1ULL << rs1) - 1ULL)) : src_avail;
						while(b) {
							const U32 rs2 = (U32)__ffsll((long long)b) - 1;
							b &= b - 1;
							local_count += opt_try_one<EMIT>(
								L,
								src,
								&m,
								oi,
								rd,
								rs1,
								rs2,
								false,
								rd_is_new_scratch,
								parent_local_id,
								dst_states,
								dst_cands_soa,
								stride,
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
						const U32 rs1 = (U32)__ffsll((long long)a) - 1;
						a &= a - 1;
						for(U32 ii = 0; ii < L->n_imms; ++ii) {
							local_count += opt_try_one<EMIT>(
								L,
								src,
								&m,
								oi,
								rd,
								rs1,
								ii,
								true,
								rd_is_new_scratch,
								parent_local_id,
								dst_states,
								dst_cands_soa,
								stride,
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
					for(U32 ii = 0; ii < L->n_imms; ++ii) {
						local_count += opt_try_one<EMIT>(
							L,
							src,
							&m,
							oi,
							rd,
							0u,
							ii,
							true,
							rd_is_new_scratch,
							parent_local_id,
							dst_states,
							dst_cands_soa,
							stride,
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
						const U32 rs1 = (U32)__ffsll((long long)a) - 1;
						a &= a - 1;
						local_count += opt_try_one<EMIT>(
							L,
							src,
							&m,
							oi,
							rd,
							rs1,
							0u,
							false,
							rd_is_new_scratch,
							parent_local_id,
							dst_states,
							dst_cands_soa,
							stride,
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

__global__ void opt_count_kernel(
	const EnumState* __restrict__ src_front, U32 n_src, EnumLayer e, U32* __restrict__ d_counts
) {
	const U32 tid = blockIdx.x * blockDim.x + threadIdx.x;
	if(tid >= n_src) { return; }

	const EnumState& src = src_front[tid];
	// count-only path: dst_* / stride / caps unused
	const U32 c = opt_expand_one<false>(&e, &src, 0, 0, 0, 0, 0, 0, 0, 0);
	d_counts[tid] = c;
}

__global__ void opt_emit_kernel(
	const EnumState* __restrict__ src_front,
	U32 n_src,
	const U64* __restrict__ d_offsets,
	U64 base_adjust,
	EnumLayer e,
	EnumState* __restrict__ dst_states,
	Instruction* __restrict__ dst_cands_soa,
	U64 stride,
	U64 cap_states,
	U64 cap_cands
) {
	const U32 tid = blockIdx.x * blockDim.x + threadIdx.x;
	if(tid >= n_src) { return; }

	const EnumState src = src_front[tid];
	const U64 base = d_offsets[tid] - base_adjust;
	opt_expand_one<true>(
		&e, &src, tid, dst_states, dst_cands_soa, stride, 0, base, cap_states, cap_cands
	);
}

__global__ void opt_emit_tuples_kernel(
	const EnumState* __restrict__ src_front,
	U32 n_src,
	const U64* __restrict__ d_offsets,
	U64 base_adjust,
	EnumLayer e,
	U64* __restrict__ dst_tuples,
	U64 cap_cands
) {
	const U32 tid = blockIdx.x * blockDim.x + threadIdx.x;
	if(tid >= n_src) { return; }

	const EnumState src = src_front[tid];
	const U64 base = d_offsets[tid] - base_adjust;
	opt_expand_one<true>(&e, &src, tid, 0, 0, 0, dst_tuples, base, 0, cap_cands);
}

__global__ void opt_build_from_tuples_kernel(
	const U64* __restrict__ d_tuples,
	U64 n_cands,
	const EnumState* __restrict__ src_front,
	const EnumMeta* __restrict__ d_meta,
	const I64* __restrict__ d_imms,
	Instruction* __restrict__ dst_cands_soa,
	U64 stride
) {
	const U64 cand_id = (U64)blockIdx.x * blockDim.x + threadIdx.x;
	if(cand_id >= n_cands) { return; }

	const U64 t = d_tuples[cand_id];
	const U32 parent_local_id = (U32)(t & 0xFFFFFFFFull);
	const U32 op_idx = (U32)((t >> 32) & 0xFFull);
	const U32 rd = (U32)((t >> 40) & 0x1Full);
	const U32 rs1 = (U32)((t >> 45) & 0x1Full);
	const U32 rs2_or_imm_idx = (U32)((t >> 50) & 0xFFull);
	const B32 is_imm = (B32)((t >> 58) & 0x1ull);

	const EnumState src = src_front[parent_local_id];
	const EnumMeta m = d_meta[op_idx];

	Instruction built;
	opt_build_inst(&m, rd, rs1, rs2_or_imm_idx, is_imm, d_imms, &built);

	const I32 build_idx = src.idx;
#pragma unroll
	for(U32 k = 0; k < MaxProgramLen; ++k) {
		const Instruction in = ((I32)k == build_idx) ? built : src.code[k];
		dst_cands_soa[(U64)k * stride + cand_id] = in;
	}
}

I32 enum_make(Enum* e, U64 batch_size) {
	*e = {};
	dmalloc(&e->d_meta, (U64)InstructionOpcode_Count * sizeof(EnumMeta));
	dmalloc(&e->d_imms, (U64)EnumImmPoolSize * sizeof(I64));
	e->n_meta = 0;
	e->n_imms_cap = EnumImmPoolSize;
	U64 capacity = Max(1024, batch_size);

	{
		U64 free_mem = 0;
		U64 total_mem = 0;
		cudaMemGetInfo(&free_mem, &total_mem);
		(void)total_mem;
		const U64 reserved = 128ull * MB(1);
		const U64 usable = free_mem > reserved ? (free_mem - reserved) : 0;
		const U64 state_mem = (2ull * sizeof(EnumState)) + sizeof(EnumProgram);
		const U64 meta_mem = sizeof(U64) + sizeof(U32) + sizeof(U64);
		const U64 per_slot = state_mem + meta_mem;
		const U64 vram_capacity = usable / per_slot;
		if(vram_capacity < capacity) { capacity = vram_capacity; }
	}

	e->capacity = capacity;
	dmalloc(&e->d_front_a, capacity * sizeof(EnumState));
	dmalloc(&e->d_front_b, capacity * sizeof(EnumState));
	dmalloc(&e->d_counts, capacity * sizeof(U32));
	dmalloc(&e->d_offsets, capacity * sizeof(U64));
	dmalloc(&e->d_out, capacity * sizeof(EnumProgram));
	dmalloc(&e->d_tuples, capacity * sizeof(U64));
	e->scan_tmp_bytes = 0;
	device_exclusive_sum(0, &e->scan_tmp_bytes, (U32*)e->d_counts, (U64*)e->d_offsets, (I32)capacity);
	dmalloc(&e->d_scan_tmp, e->scan_tmp_bytes);

	return 0;
}

void enum_free(Enum* e) {
	if(e->d_scan_tmp) { cudaFree(e->d_scan_tmp); }
	if(e->d_tuples) { cudaFree(e->d_tuples); }
	if(e->d_out) { cudaFree(e->d_out); }
	if(e->d_offsets) { cudaFree(e->d_offsets); }
	if(e->d_counts) { cudaFree(e->d_counts); }
	if(e->d_front_b) { cudaFree(e->d_front_b); }
	if(e->d_front_a) { cudaFree(e->d_front_a); }
	if(e->d_imms) { cudaFree(e->d_imms); }
	if(e->d_meta) { cudaFree(e->d_meta); }
	*e = {};
}

void enum_run(Enum* e, EnumOptions* opt) {
	e->out_d_cands = (Instruction*)e->d_out;
	e->out_cand_stride = 0;
	e->out_n_cands = 0;
	e->last_layer_ready = false;
	e->d_last_front = 0;
	e->last_layer_n_front = 0;
	e->last_layer_cursor = 0;
	e->last_layer_cap = 0;
	if(opt->cap == 0 || opt->prog_len == 0) { return; }

	// meta host
	EnumMeta h_meta[InstructionOpcode_Count];
	U32 n_meta = 0;
	enum_make_meta_host(opt->pool, h_meta, &n_meta);
	if(n_meta == 0) { return; }

	const U64 live_in = opt->live_in_mask & ~1ULL;
	const U64 preserved = live_in | opt->live_out_mask;

	htod_memcpy(e->d_meta, h_meta, n_meta * sizeof(EnumMeta));
	htod_memcpy(e->d_imms, opt->imms->vals, opt->imms->n * sizeof(I64));
	EnumMeta* d_meta = (EnumMeta*)e->d_meta;
	I64* d_imms = (I64*)e->d_imms;
	const U64 capacity = e->capacity < opt->cap ? e->capacity : opt->cap;

	EnumState* d_front_a = (EnumState*)e->d_front_a;
	EnumState* d_front_b = (EnumState*)e->d_front_b;
	U32* d_counts = (U32*)e->d_counts;
	U64* d_offsets = (U64*)e->d_offsets;
	void* d_scan_tmp = e->d_scan_tmp;
	U64 scan_tmp_bytes = e->scan_tmp_bytes;

	// init root
	EnumState h_root;
	for(U32 k = 0; k < MaxProgramLen; ++k) {
		h_root.code[k] = {};
		h_root.code[k].op = InstructionOpcode_Nop;
	}
	h_root.demanded = opt->live_out_mask;
	h_root.used_scratch = 0;
	h_root.idx = (I32)opt->prog_len - 1;
	h_root._pad = 0;
	htod_memcpy(d_front_a, &h_root, sizeof(EnumState));
	U64 n_front = 1;
	U64 scratch_mask = 0;

	{
		const U32 hi = opt->max_scratch < 32 ? opt->max_scratch : 32;
		for(U32 r = 5; r < hi; ++r) {
			const U64 bit = 1ULL << r;
			if(!(preserved & bit)) { scratch_mask |= bit; }
		}
	}

	// expand upper layers, stop when we reach the last layer (layer == 0)
	for(I32 layer = (I32)opt->prog_len - 1; layer >= 0; --layer) {
		if(n_front == 0) { break; }
		U64 src_avail;
		if(layer == 0) {
			src_avail = live_in | 1ULL;
		} else {
			src_avail = live_in | 1ULL | scratch_mask | opt->live_out_mask;
		}

		// init layer context
		EnumLayer lctx;
		lctx.meta = d_meta;
		lctx.n_meta = n_meta;
		lctx.imms = d_imms;
		lctx.n_imms = opt->imms->n;
		lctx.live_in_mask = live_in;
		lctx.live_out_mask = opt->live_out_mask;
		lctx.preserved_mask = preserved;
		lctx.src_avail = src_avail;
		lctx.scratch_mask = scratch_mask;
		lctx.max_scratch = opt->max_scratch;
		lctx.is_last_layer = (layer == 0);

		// at the last layer, don't emit here. count the entire last-layer
		// frontier once (so enum_emit_batch can binary-search the cached
		// prefix-sum across all chunks) and stash everything for paginated
		// emission.
		if(lctx.is_last_layer) {
			if(n_front > 0) {
				const U32 threads_c = 256;
				const U32 blocks_c = (U32)((n_front + threads_c - 1) / threads_c);
				opt_count_kernel<<<blocks_c, threads_c>>>(d_front_a, (U32)n_front, lctx, d_counts);
				check_cuda(cudaGetLastError(), "enum count kernel (last layer)");
				device_exclusive_sum(d_scan_tmp, &scan_tmp_bytes, d_counts, d_offsets, (I32)n_front);
				// cudaMemcpy in enum_emit_batch will implicitly sync these.
			}

			e->last_layer_ready = true;
			e->d_last_front = d_front_a;
			e->last_layer_n_front = n_front;
			e->last_layer_cursor = 0;
			e->last_layer_cap = capacity;
			e->last_layer_ctx = lctx;
			break;
		}

		const U32 threads = 256;
		const U32 blocks = (U32)((n_front + threads - 1) / threads);

		// count
		opt_count_kernel<<<blocks, threads>>>(d_front_a, (U32)n_front, lctx, d_counts);
		check_cuda(cudaGetLastError(), "enum count kernel");
		device_exclusive_sum(d_scan_tmp, &scan_tmp_bytes, d_counts, d_offsets, (I32)n_front);

		// copyback
		U64 last_off = 0;
		U32 last_cnt = 0;
		dtoh_memcpy(&last_off, d_offsets + (n_front - 1), sizeof(U64));
		dtoh_memcpy(&last_cnt, d_counts + (n_front - 1), sizeof(U32));
		const U64 total = last_off + (U64)last_cnt;

		if(total > 0) {
			const U64 cap_states = capacity;

			// emit next-layer frontier into d_front_b
			opt_emit_kernel<<<blocks, threads>>>(
				d_front_a, (U32)n_front, d_offsets, 0, lctx, d_front_b, 0, 0, cap_states, 0
			);
			check_cuda(cudaGetLastError(), "enum emit kernel");
		}

		n_front = total < capacity ? total : capacity;
		EnumState* tmp = d_front_a;
		d_front_a = d_front_b;
		d_front_b = tmp;
	}
}

U64 enum_find_chunk_fit(U64* d_offsets, U64 cursor, U64 n_front, U64 total, U64 cap) {
	if(cursor >= n_front) { return 0; }

	// read offsets[cursor] (= base for the chunk)
	U64 base_off = 0;
	if(cursor > 0) { dtoh_memcpy(&base_off, d_offsets + cursor, sizeof(U64)); }

	const U64 tail_total = total - base_off;
	const U64 remaining = n_front - cursor;
	if(tail_total <= cap) { return remaining; }

	U64 lo = 0;
	U64 hi = remaining;
	while(lo + 1 < hi) {
		const U64 mid = lo + (hi - lo) / 2;
		U64 off = 0;
		const U64 absolute_idx = cursor + mid;
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
	e->out_d_cands = (Instruction*)e->d_out;
	e->out_cand_stride = e->last_layer_cap;

	if(!e->last_layer_ready) { return 0; }
	if(e->last_layer_cursor >= e->last_layer_n_front) { return 0; }

	EnumState* d_last_front = (EnumState*)e->d_last_front;
	U32* d_counts = (U32*)e->d_counts;
	U64* d_offsets = (U64*)e->d_offsets;
	Instruction* d_out_soa = (Instruction*)e->d_out;
	const U64 cap = e->last_layer_cap;
	const EnumLayer lctx = e->last_layer_ctx;
	const U64 cursor = e->last_layer_cursor;
	const U64 n_front = e->last_layer_n_front;

	U64 last_off = 0;
	U32 last_cnt = 0;
	dtoh_memcpy(&last_off, d_offsets + (n_front - 1), sizeof(U64));
	dtoh_memcpy(&last_cnt, d_counts + (n_front - 1), sizeof(U32));
	const U64 total = last_off + (U64)last_cnt;

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
		const U32 threads = 256;
		U64* d_tuples = (U64*)e->d_tuples;
		EnumMeta* d_meta = (EnumMeta*)e->d_meta;
		I64* d_imms = (I64*)e->d_imms;

		// phase 1: per-parent threads write a packed 64-bit tuple per child
		{
			const U32 emit_blocks = (U32)((k + threads - 1) / threads);
			opt_emit_tuples_kernel<<<emit_blocks, threads>>>(
				d_last_front + cursor, (U32)k, d_offsets + cursor, base_off, lctx, d_tuples, cap
			);
			check_cuda(cudaGetLastError(), "enum emit tuples kernel");
		}

		// phase 2: per-cand_id threads decode their tuple, fetch the parent's EnumState, build the
		// chosen Instruction, and write the cand entry
		{
			const U32 build_blocks = (U32)((emitted + threads - 1) / threads);
			opt_build_from_tuples_kernel<<<build_blocks, threads>>>(
				d_tuples, emitted, d_last_front + cursor, d_meta, d_imms, d_out_soa, cap
			);
			check_cuda(cudaGetLastError(), "enum build-from-tuples kernel");
			check_cuda(cudaDeviceSynchronize(), "enum emit sync");
		}
	}

	e->last_layer_cursor += k;
	e->out_d_cands = d_out_soa;
	e->out_n_cands = emitted;
	return emitted;
}
