#include "optimize/enumerate.cuh"
#include "util/device.h"
#include <cub/cub.cuh>

void enum_make_opcode_pool(EnumOpcodePool* pool, u32 ext_mask) {
	*pool = {};

	for(u32 i = 0; i < (u32)InstructionOpcode_Count; ++i) {
		const InstructionInfo& s = instruction_db_host.row[i];
		if(s.op == InstructionOpcode_Nop) { continue; }
		if(!(s.ext & ext_mask)) { continue; }
		pool->ops[pool->n++] = (InstructionOpcode)i;
	}
}

void enum_make_imm_pool(EnumImmPool* pool) {
	// TODO: add imms from programm etc.
	*pool = {};

	for(i64 v = -8; v <= 8; ++v) { pool->vals[pool->n++] = v; }
	const i64 extra[] = {16, 32, 63, 64, 0xFF, 0xFFFF};
	for(i64 v : extra) { pool->vals[pool->n++] = v; }
}

void enum_make_meta_host(const EnumOpcodePool* pool, EnumMeta* out, u32* out_n) {
	u32 n = 0;
	for(u32 i = 0; i < pool->n; ++i) {
		const InstructionOpcode op = pool->ops[i];
		const InstructionInfo& info = instruction_db_host.row[op];

		EnumMeta m;
		m.op = (u16)op;
		m.commutative = (u8)info.commutative;
		m.dst_slot = info.dst_slot;
		m.src_slot = info.src_slot;
		m.src2_slot = info.src2_slot;
		m.imm_slot = -1;

		for(u32 k = 0; k < 4; ++k) {
			if(info.operands[k] == InstructionOperandType_Imm) {
				m.imm_slot = (i8)k;
				break;
			}
		}

		const b32 has_rs1 = info.src_slot >= 0;
		const b32 has_rs2 = info.src2_slot >= 0;
		const b32 has_imm = m.imm_slot >= 0;

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

__device__ __forceinline__ void opt_build_inst(const EnumMeta& m, u32 rd,
																							 u32 rs1, u32 rs2_or_imm_idx,
																							 b32 is_imm, const i64* imms,
																							 Instruction* out) {
	Instruction in;
	in.op = (InstructionOpcode)m.op;
#pragma unroll
	for(u32 k = 0; k < 4; ++k) { in.operands[k].imm = 0; }

	in.operands[m.dst_slot].reg = (Reg)rd;
	if(m.src_slot >= 0) { in.operands[m.src_slot].reg = (Reg)rs1; }
	if(!is_imm && m.src2_slot >= 0) {
		in.operands[m.src2_slot].reg = (Reg)rs2_or_imm_idx;
	}
	if(is_imm && m.imm_slot >= 0) {
		in.operands[m.imm_slot].imm = (u64)imms[rs2_or_imm_idx];
	}

	*out = in;
}

template<b32 EMIT>
__device__ __forceinline__ u32 opt_try_one(
	const EnumLayer& L, const EnumState& src, const EnumMeta& m, u32 rd,
	u32 rs1, u32 rs2_or_imm_idx, b32 is_imm, b32 rd_is_new_scratch,
	EnumState* dst_states, EnumProgram* dst_cands, u64 write_base,
	u32* write_local, u64 cap_states, u64 cap_cands) {
	u64 new_demanded = src.demanded & ~(1ULL << rd);
	if(m.src_slot >= 0) {
		const u32 r = rs1;
		if(r != 0 && !(L.live_in_mask & (1ULL << r))) { new_demanded |= 1ULL << r; }
	}
	if(!is_imm && m.src2_slot >= 0) {
		const u32 r = rs2_or_imm_idx;
		if(r != 0 && !(L.live_in_mask & (1ULL << r))) { new_demanded |= 1ULL << r; }
	}

	u64 new_used_scratch = src.used_scratch;
	if(rd_is_new_scratch) { new_used_scratch |= 1ULL << rd; }

	if(L.is_last_layer) {
		if((new_demanded & ~L.live_in_mask) != 0) { return 0; }
	} else {
		if(new_demanded == 0) { return 0; }
	}

	if constexpr(EMIT) {
		const u64 slot = write_base + (u64)(*write_local);
		++(*write_local);
		if(L.is_last_layer) {
			if(slot < cap_cands) {
				EnumProgram c;
#pragma unroll
				for(u32 k = 0; k < MaxProgramLen; ++k) { c.code[k] = src.code[k]; }
				opt_build_inst(m, rd, rs1, rs2_or_imm_idx, is_imm, L.imms,
											 &c.code[src.idx]);
				dst_cands[slot] = c;
			}
		} else {
			if(slot < cap_states) {
				EnumState ns;
#pragma unroll
				for(u32 k = 0; k < MaxProgramLen; ++k) { ns.code[k] = src.code[k]; }
				opt_build_inst(m, rd, rs1, rs2_or_imm_idx, is_imm, L.imms,
											 &ns.code[src.idx]);
				ns.demanded = new_demanded;
				ns.used_scratch = new_used_scratch;
				ns.idx = src.idx - 1;
				ns._pad = 0;
				dst_states[slot] = ns;
			}
		}
	}

	return 1;
}

// expand one frontier node
template<b32 EMIT>
__device__ u32 opt_expand_one(const EnumLayer& L, const EnumState& src,
															EnumState* dst_states, EnumProgram* dst_cands,
															u64 write_base, u64 cap_states, u64 cap_cands) {
	if(src.demanded == 0) { return 0; }
	const u64 src_avail = L.src_avail;
	const u64 unused_scratch = L.scratch_mask & ~src.used_scratch;
	u64 next_scratch_bit = 0;
	if(unused_scratch != 0) {
		next_scratch_bit =
			unused_scratch & (~unused_scratch + 1ULL); // isolate lowest
	}
	const u64 low_regs = 0x1EULL; // 1 - 4
	const u64 valid_rd_pool =
		L.preserved_mask | src.used_scratch | next_scratch_bit | low_regs;
	const u64 dst_avail = src.demanded & valid_rd_pool & ~1ULL; // never write x0

	if(dst_avail == 0) { return 0; }

	u32 local_count = 0;
	u32 write_local = 0;

	for(u32 oi = 0; oi < L.n_meta; ++oi) {
		const EnumMeta m = L.meta[oi];

		// iterate dst registers
		u64 dst_iter = dst_avail;
		while(dst_iter) {
			const u32 rd = (u32)__ffsll((long long)dst_iter) - 1;
			const u64 rd_bit = dst_iter & (~dst_iter + 1ULL);
			dst_iter &= dst_iter - 1;
			const b32 rd_is_new_scratch =
				(rd_bit == next_scratch_bit) && (next_scratch_bit != 0);

			switch(m.shape) {
				case InstructionShape_RRR: {
					u64 a = src_avail;
					while(a) {
						const u32 rs1 = (u32)__ffsll((long long)a) - 1;
						a &= a - 1;
						u64 b =
							m.commutative ? (src_avail & ~((1ULL << rs1) - 1ULL)) : src_avail;
						while(b) {
							const u32 rs2 = (u32)__ffsll((long long)b) - 1;
							b &= b - 1;
							local_count += opt_try_one<EMIT>(
								L, src, m, rd, rs1, rs2, false, rd_is_new_scratch, dst_states,
								dst_cands, write_base, &write_local, cap_states, cap_cands);
						}
					}
					break;
				}
				case InstructionShape_RRI: {
					u64 a = src_avail;
					while(a) {
						const u32 rs1 = (u32)__ffsll((long long)a) - 1;
						a &= a - 1;
						for(u32 ii = 0; ii < L.n_imms; ++ii) {
							local_count += opt_try_one<EMIT>(
								L, src, m, rd, rs1, ii, true, rd_is_new_scratch, dst_states,
								dst_cands, write_base, &write_local, cap_states, cap_cands);
						}
					}
					break;
				}
				case InstructionShape_RI: {
					for(u32 ii = 0; ii < L.n_imms; ++ii) {
						local_count += opt_try_one<EMIT>(
							L, src, m, rd, 0u, ii, true, rd_is_new_scratch, dst_states,
							dst_cands, write_base, &write_local, cap_states, cap_cands);
					}
					break;
				}
				case InstructionShape_RR: {
					u64 a = src_avail;
					while(a) {
						const u32 rs1 = (u32)__ffsll((long long)a) - 1;
						a &= a - 1;
						local_count += opt_try_one<EMIT>(
							L, src, m, rd, rs1, 0u, false, rd_is_new_scratch, dst_states,
							dst_cands, write_base, &write_local, cap_states, cap_cands);
					}
					break;
				}
			}
		}
	}

	return local_count;
}

__global__ void opt_count_kernel(const EnumState* __restrict__ src_front,
																 u32 n_src, EnumLayer e,
																 u32* __restrict__ d_counts) {
	const u32 tid = blockIdx.x * blockDim.x + threadIdx.x;
	if(tid >= n_src) { return; }

	const EnumState& src = src_front[tid];
	const u32 c = opt_expand_one<false>(e, src, nullptr, nullptr, 0, 0, 0);
	d_counts[tid] = c;
}

__global__ void opt_emit_kernel(const EnumState* __restrict__ src_front,
																u32 n_src, const u64* __restrict__ d_offsets,
																EnumLayer e,
																EnumState* __restrict__ dst_states,
																EnumProgram* __restrict__ dst_cands,
																u64 cap_states, u64 cap_cands) {
	const u32 tid = blockIdx.x * blockDim.x + threadIdx.x;
	if(tid >= n_src) { return; }

	const EnumState src = src_front[tid];
	const u64 base = d_offsets[tid];
	opt_expand_one<true>(e, src, dst_states, dst_cands, base, cap_states,
											 cap_cands);
}

i32 enum_make(Enum* e, u64 batch_size) {
	*e = {};
	dmalloc(&e->d_meta, (u64)InstructionOpcode_Count * sizeof(EnumMeta));
	dmalloc(&e->d_imms, (u64)64 * sizeof(i64));
	e->n_meta = 0;
	e->n_imms_cap = 64;
	u64 capacity = MAX(1024, batch_size);

	{
		u64 free_mem = 0;
		u64 total_mem = 0;
		cudaMemGetInfo(&free_mem, &total_mem);
		(void)total_mem;
		const u64 reserved = 128ull * MB(1);
		const u64 usable = free_mem > reserved ? (free_mem - reserved) : 0;
		const u64 state_mem = (2ull * sizeof(EnumState)) + sizeof(EnumProgram);
		const u64 meta_mem = sizeof(u64) + sizeof(u32);
		const u64 per_slot = state_mem + meta_mem;
		const u64 vram_capacity = usable / per_slot;
		if(vram_capacity < capacity) { capacity = vram_capacity; }
	}

	e->capacity = capacity;
	dmalloc(&e->d_front_a, capacity * sizeof(EnumState));
	dmalloc(&e->d_front_b, capacity * sizeof(EnumState));
	dmalloc(&e->d_counts, capacity * sizeof(u32));
	dmalloc(&e->d_offsets, capacity * sizeof(u64));
	dmalloc(&e->d_out, capacity * sizeof(EnumProgram));
	e->scan_tmp_bytes = 0;

	// TODO: cleanup
	cub::DeviceScan::ExclusiveSum(nullptr, e->scan_tmp_bytes,
																(u32*)e->d_counts, (u64*)e->d_offsets,
																(i32)capacity);
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
	u32 n_meta = 0;
	enum_make_meta_host(opt->pool, h_meta, &n_meta);
	if(n_meta == 0) { return; }

	const u64 live_in = opt->live_in_mask & ~1ULL;
	const u64 preserved = live_in | opt->live_out_mask;

	htod_memcpy(e->d_meta, h_meta, n_meta * sizeof(EnumMeta));
	htod_memcpy(e->d_imms, opt->imms->vals, opt->imms->n * sizeof(i64));
	EnumMeta* d_meta = (EnumMeta*)e->d_meta;
	i64* d_imms = (i64*)e->d_imms;
	const u64 capacity = e->capacity < opt->cap ? e->capacity : opt->cap;

	EnumState* d_front_a = (EnumState*)e->d_front_a;
	EnumState* d_front_b = (EnumState*)e->d_front_b;
	u32* d_counts = (u32*)e->d_counts;
	u64* d_offsets = (u64*)e->d_offsets;
	EnumProgram* d_out = (EnumProgram*)e->d_out;
	void* d_scan_tmp = e->d_scan_tmp;
	size_t scan_tmp_bytes = e->scan_tmp_bytes;

	// init root
	EnumState h_root;
	for(u32 k = 0; k < MaxProgramLen; ++k) {
		h_root.code[k] = {};
		h_root.code[k].op = InstructionOpcode_Nop;
	}
	h_root.demanded = opt->live_out_mask;
	h_root.used_scratch = 0;
	h_root.idx = (i32)opt->prog_len - 1;
	h_root._pad = 0;
	htod_memcpy(d_front_a, &h_root, sizeof(EnumState));
	u64 n_front = 1;
	u64 scratch_mask = 0;

	{
		const u32 hi = opt->max_scratch < 32 ? opt->max_scratch : 32;
		for(u32 r = 5; r < hi; ++r) {
			const u64 bit = 1ULL << r;
			if(!(preserved & bit)) { scratch_mask |= bit; }
		}
	}

	u64 emitted_cands = 0;

	// expand candidate frontier
	for(i32 layer = (i32)opt->prog_len - 1; layer >= 0; --layer) {
		if(n_front == 0) { break; }
		u64 src_avail;
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

		const u32 threads = 256;
		const u32 blocks = (u32)((n_front + threads - 1) / threads);

		// count
		opt_count_kernel<<<blocks, threads>>>(d_front_a, (u32)n_front, lctx,
																					d_counts);
		check_cuda(cudaGetLastError(), "enum count kernel");
		// TODO: cleanup
		cub::DeviceScan::ExclusiveSum(d_scan_tmp, scan_tmp_bytes, d_counts,
																	d_offsets, (i32)n_front);

		// copyback
		u64 last_off = 0;
		u32 last_cnt = 0;
		dtoh_memcpy(&last_off, d_offsets + (n_front - 1), sizeof(u64));
		dtoh_memcpy(&last_cnt, d_counts + (n_front - 1), sizeof(u32));
		const u64 total = last_off + (u64)last_cnt;

		if(total > 0) {
			const u64 cap_states = lctx.is_last_layer ? 0 : capacity;
			const u64 cap_cands = lctx.is_last_layer ? (capacity - emitted_cands) : 0;

			EnumState* dst_states = lctx.is_last_layer ? nullptr : d_front_b;
			EnumProgram* dst_cands = nullptr;
			if(lctx.is_last_layer) { dst_cands = d_out + emitted_cands; }

			// emit candidates
			opt_emit_kernel<<<blocks, threads>>>(d_front_a, (u32)n_front, d_offsets,
																					 lctx, dst_states, dst_cands,
																					 cap_states, cap_cands);
			check_cuda(cudaGetLastError(), "enum emit kernel");
		}

		if(lctx.is_last_layer) {
			const u64 remaining = capacity - emitted_cands;
			const u64 written = total < remaining ? total : remaining;
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