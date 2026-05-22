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

void enum_make_imm_pool(EnumImmPool* pool) {
	// TODO: add imms from programm etc.
	*pool = {};

	for(I64 v = -8; v <= 8; ++v) { pool->vals[pool->n++] = v; }
	const I64 extra[] = {16, 32, 63, 64, 0xFF, 0xFFFF};
	for(I64 v : extra) { pool->vals[pool->n++] = v; }
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

__device__ __forceinline__ void opt_build_inst(const EnumMeta* m, U32 rd, U32 rs1,
																							 U32 rs2_or_imm_idx, B32 is_imm, const I64* imms,
																							 Instruction* out) {
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

template<B32 EMIT>
__device__ __forceinline__ U32 opt_try_one(const EnumLayer* L, const EnumState* src,
																					 const EnumMeta* m, U32 rd, U32 rs1, U32 rs2_or_imm_idx,
																					 B32 is_imm, B32 rd_is_new_scratch, EnumState* dst_states,
																					 EnumProgram* dst_cands, U64 write_base, U32* write_local,
																					 U64 cap_states, U64 cap_cands) {
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
			if(slot < cap_cands) {
				EnumProgram c;
#pragma unroll
				for(U32 k = 0; k < MaxProgramLen; ++k) { c.code[k] = src->code[k]; }
				opt_build_inst(m, rd, rs1, rs2_or_imm_idx, is_imm, L->imms, &c.code[src->idx]);
				dst_cands[slot] = c;
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
__device__ U32 opt_expand_one(const EnumLayer* L, const EnumState* src, EnumState* dst_states,
															EnumProgram* dst_cands, U64 write_base, U64 cap_states,
															U64 cap_cands) {
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
							local_count +=
								opt_try_one<EMIT>(L, src, &m, rd, rs1, rs2, false, rd_is_new_scratch, dst_states,
																	dst_cands, write_base, &write_local, cap_states, cap_cands);
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
							local_count +=
								opt_try_one<EMIT>(L, src, &m, rd, rs1, ii, true, rd_is_new_scratch, dst_states,
																	dst_cands, write_base, &write_local, cap_states, cap_cands);
						}
					}
					break;
				}
				case InstructionShape_RI: {
					for(U32 ii = 0; ii < L->n_imms; ++ii) {
						local_count +=
							opt_try_one<EMIT>(L, src, &m, rd, 0u, ii, true, rd_is_new_scratch, dst_states,
																dst_cands, write_base, &write_local, cap_states, cap_cands);
					}
					break;
				}
				case InstructionShape_RR: {
					U64 a = src_avail;
					while(a) {
						const U32 rs1 = (U32)__ffsll((long long)a) - 1;
						a &= a - 1;
						local_count +=
							opt_try_one<EMIT>(L, src, &m, rd, rs1, 0u, false, rd_is_new_scratch, dst_states,
																dst_cands, write_base, &write_local, cap_states, cap_cands);
					}
					break;
				}
			}
		}
	}

	return local_count;
}

__global__ void opt_count_kernel(const EnumState* __restrict__ src_front, U32 n_src, EnumLayer e,
																 U32* __restrict__ d_counts) {
	const U32 tid = blockIdx.x * blockDim.x + threadIdx.x;
	if(tid >= n_src) { return; }

	const EnumState& src = src_front[tid];
	const U32 c = opt_expand_one<false>(&e, &src, 0, 0, 0, 0, 0);
	d_counts[tid] = c;
}

__global__ void opt_emit_kernel(const EnumState* __restrict__ src_front, U32 n_src,
																const U64* __restrict__ d_offsets, EnumLayer e,
																EnumState* __restrict__ dst_states,
																EnumProgram* __restrict__ dst_cands, U64 cap_states,
																U64 cap_cands) {
	const U32 tid = blockIdx.x * blockDim.x + threadIdx.x;
	if(tid >= n_src) { return; }

	const EnumState src = src_front[tid];
	const U64 base = d_offsets[tid];
	opt_expand_one<true>(&e, &src, dst_states, dst_cands, base, cap_states, cap_cands);
}

I32 enum_make(Enum* e, U64 batch_size) {
	*e = {};
	dmalloc(&e->d_meta, (U64)InstructionOpcode_Count * sizeof(EnumMeta));
	dmalloc(&e->d_imms, (U64)64 * sizeof(I64));
	e->n_meta = 0;
	e->n_imms_cap = 64;
	U64 capacity = Max(1024, batch_size);

	{
		U64 free_mem = 0;
		U64 total_mem = 0;
		cudaMemGetInfo(&free_mem, &total_mem);
		(void)total_mem;
		const U64 reserved = 128ull * MB(1);
		const U64 usable = free_mem > reserved ? (free_mem - reserved) : 0;
		const U64 state_mem = (2ull * sizeof(EnumState)) + sizeof(EnumProgram);
		const U64 meta_mem = sizeof(U64) + sizeof(U32);
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
	e->scan_tmp_bytes = 0;
	device_exclusive_sum(0, &e->scan_tmp_bytes, (U32*)e->d_counts, (U64*)e->d_offsets, (I32)capacity);
	dmalloc(&e->d_scan_tmp, e->scan_tmp_bytes);

	return 0;
}

void enum_free(Enum* e) {
	if(e->d_scan_tmp) { cudaFree(e->d_scan_tmp); }
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
	e->out_d_cands = (EnumProgram*)e->d_out;
	e->out_n_cands = 0;
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
	EnumProgram* d_out = (EnumProgram*)e->d_out;
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

	U64 emitted_cands = 0;

	// expand candidate frontier
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
			const U64 cap_states = lctx.is_last_layer ? 0 : capacity;
			const U64 cap_cands = lctx.is_last_layer ? (capacity - emitted_cands) : 0;

			EnumState* dst_states = lctx.is_last_layer ? 0 : d_front_b;
			EnumProgram* dst_cands = 0;
			if(lctx.is_last_layer) { dst_cands = d_out + emitted_cands; }

			// emit candidates
			opt_emit_kernel<<<blocks, threads>>>(d_front_a, (U32)n_front, d_offsets, lctx, dst_states,
																					 dst_cands, cap_states, cap_cands);
			check_cuda(cudaGetLastError(), "enum emit kernel");
		}

		if(lctx.is_last_layer) {
			const U64 remaining = capacity - emitted_cands;
			const U64 written = total < remaining ? total : remaining;
			emitted_cands += written;
			n_front = 0;
		} else {
			n_front = total < capacity ? total : capacity;
			EnumState* tmp = d_front_a;
			d_front_a = d_front_b;
			d_front_b = tmp;
		}
	}

	if(emitted_cands > 0) { check_cuda(cudaDeviceSynchronize(), "enum sync"); }
	e->out_d_cands = d_out;
	e->out_n_cands = emitted_cands;
}