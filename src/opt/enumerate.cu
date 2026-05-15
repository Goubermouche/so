#include "opt/enumerate.cuh"
#include "utl/device.h"
#include <cub/cub.cuh>

opt_opcode_pool opt_build_opcode_pool(u32 ext_mask) {
	opt_opcode_pool p = {};

	for(u32 i = 0; i < (u32)OP_COUNT; ++i) {
		const cpu_inst_spec& s = CPU_INST_DB_HOST.row[i];
		if(s.op == OP_NOP) { continue; }
		if(!(s.ext & ext_mask)) { continue; }
		p.ops[p.n_ops++] = (cpu_opcode)i;
	}

	return p;
}

opt_imm_pool opt_build_default_imm_pool() {
	opt_imm_pool p = {};

	for(i64 v = -8; v <= 8; ++v) { p.vals[p.n++] = v; }
	const i64 extra[] = {16, 32, 63, 64, 0xFF, 0xFFFF};
	for(i64 v : extra) { p.vals[p.n++] = v; }

	return p;
}

static void opt_build_meta_host(const opt_opcode_pool* pool, opt_op_meta* out, u32* out_n) {
	u32 n = 0;
	for(u32 i = 0; i < pool->n_ops; ++i) {
		const cpu_opcode op = pool->ops[i];
		const cpu_inst_spec& spec = CPU_INST_DB_HOST.row[op];

		opt_op_meta m;
		m.op = (u16)op;
		m.commutative = (u8)spec.commutative;
		m.dst_slot = spec.dst_slot;
		m.src_slot = spec.src_slot;
		m.src2_slot = spec.src2_slot;
		m.imm_slot = -1;
		for(u32 k = 0; k < 4; ++k) {
			if(spec.operands[k] == cpu_inst_spec::IMM) {
				m.imm_slot = (i8)k;
				break;
			}
		}

		const b32 has_rs1 = spec.src_slot >= 0;
		const b32 has_rs2 = spec.src2_slot >= 0;
		const b32 has_imm = m.imm_slot >= 0;

		if(has_rs1 && has_rs2) {
			m.shape = OPT_SHAPE_RRR;
		} else if(has_rs1 && has_imm) {
			m.shape = OPT_SHAPE_RRI;
		} else if(has_imm) {
			m.shape = OPT_SHAPE_RI;
		} else if(has_rs1) {
			m.shape = OPT_SHAPE_RR;
		} else {
			continue;
		}

		out[n++] = m;
	}
	*out_n = n;
}

typedef struct opt_layer_ctx {
	const opt_op_meta* meta;
	u32 n_meta;
	const i64* imms;
	u32 n_imms;
	u64 live_in_mask;
	u64 live_out_mask;
	u64 preserved_mask;
	u64 src_avail;
	u64 scratch_mask;
	u32 max_scratch;
	b32 is_last_layer;
} opt_layer_ctx;

__device__ __forceinline__ void opt_build_inst(const opt_op_meta& m, u32 rd, u32 rs1,
																							 u32 rs2_or_imm_idx, b32 is_imm, const i64* imms,
																							 cpu_inst* out) {
	cpu_inst in;
	in.op = (cpu_opcode)m.op;
#pragma unroll
	for(u32 k = 0; k < 4; ++k) { in.operands[k].i = 0; }

	in.operands[m.dst_slot].reg = (cpu_reg_index)rd;
	if(m.src_slot >= 0) { in.operands[m.src_slot].reg = (cpu_reg_index)rs1; }
	if(!is_imm && m.src2_slot >= 0) { in.operands[m.src2_slot].reg = (cpu_reg_index)rs2_or_imm_idx; }
	if(is_imm && m.imm_slot >= 0) { in.operands[m.imm_slot].i = (u64)imms[rs2_or_imm_idx]; }

	*out = in;
}

template <bool EMIT>
__device__ __forceinline__ u32 opt_try_one(const opt_layer_ctx& L, const opt_state& src,
																					 const opt_op_meta& m, u32 rd, u32 rs1,
																					 u32 rs2_or_imm_idx, b32 is_imm, b32 rd_is_new_scratch,
																					 opt_state* dst_states, opt_candidate* dst_cands,
																					 u64 write_base, u32* write_local, u64 cap_states,
																					 u64 cap_cands) {
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
				opt_candidate c;
#pragma unroll
				for(u32 k = 0; k < SYNTH_PROG_LEN; ++k) { c.code[k] = src.code[k]; }
				opt_build_inst(m, rd, rs1, rs2_or_imm_idx, is_imm, L.imms, &c.code[src.idx]);
				dst_cands[slot] = c;
			}
		} else {
			if(slot < cap_states) {
				opt_state ns;
#pragma unroll
				for(u32 k = 0; k < SYNTH_PROG_LEN; ++k) { ns.code[k] = src.code[k]; }
				opt_build_inst(m, rd, rs1, rs2_or_imm_idx, is_imm, L.imms, &ns.code[src.idx]);
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

template <bool EMIT>
__device__ u32 opt_expand_one(const opt_layer_ctx& L, const opt_state& src, opt_state* dst_states,
															opt_candidate* dst_cands, u64 write_base, u64 cap_states,
															u64 cap_cands) {
	if(src.demanded == 0) { return 0; }
	const u64 src_avail = L.src_avail;
	const u64 unused_scratch = L.scratch_mask & ~src.used_scratch;
	u64 next_scratch_bit = 0;
	if(unused_scratch != 0) {
		next_scratch_bit = unused_scratch & (~unused_scratch + 1ULL); // isolate lowest
	}
	const u64 low_regs = 0x1EULL; // 1 - 4
	const u64 valid_rd_pool = L.preserved_mask | src.used_scratch | next_scratch_bit | low_regs;
	const u64 dst_avail = src.demanded & valid_rd_pool & ~1ULL; // never write x0

	if(dst_avail == 0) { return 0; }

	u32 local_count = 0;
	u32 write_local = 0;

	for(u32 oi = 0; oi < L.n_meta; ++oi) {
		const opt_op_meta m = L.meta[oi];

		// iterate dst registers
		u64 dst_iter = dst_avail;
		while(dst_iter) {
			const u32 rd = (u32)__ffsll((long long)dst_iter) - 1;
			const u64 rd_bit = dst_iter & (~dst_iter + 1ULL);
			dst_iter &= dst_iter - 1;
			const b32 rd_is_new_scratch = (rd_bit == next_scratch_bit) && (next_scratch_bit != 0);

			switch(m.shape) {
				case OPT_SHAPE_RRR: {
					u64 a = src_avail;
					while(a) {
						const u32 rs1 = (u32)__ffsll((long long)a) - 1;
						a &= a - 1;
						u64 b = m.commutative ? (src_avail & ~((1ULL << rs1) - 1ULL)) : src_avail;
						while(b) {
							const u32 rs2 = (u32)__ffsll((long long)b) - 1;
							b &= b - 1;
							local_count +=
								opt_try_one<EMIT>(L, src, m, rd, rs1, rs2, false, rd_is_new_scratch, dst_states,
																	dst_cands, write_base, &write_local, cap_states, cap_cands);
						}
					}
					break;
				}
				case OPT_SHAPE_RRI: {
					u64 a = src_avail;
					while(a) {
						const u32 rs1 = (u32)__ffsll((long long)a) - 1;
						a &= a - 1;
						for(u32 ii = 0; ii < L.n_imms; ++ii) {
							local_count +=
								opt_try_one<EMIT>(L, src, m, rd, rs1, ii, true, rd_is_new_scratch, dst_states,
																	dst_cands, write_base, &write_local, cap_states, cap_cands);
						}
					}
					break;
				}
				case OPT_SHAPE_RI: {
					for(u32 ii = 0; ii < L.n_imms; ++ii) {
						local_count +=
							opt_try_one<EMIT>(L, src, m, rd, 0u, ii, true, rd_is_new_scratch, dst_states,
																dst_cands, write_base, &write_local, cap_states, cap_cands);
					}
					break;
				}
				case OPT_SHAPE_RR: {
					u64 a = src_avail;
					while(a) {
						const u32 rs1 = (u32)__ffsll((long long)a) - 1;
						a &= a - 1;
						local_count +=
							opt_try_one<EMIT>(L, src, m, rd, rs1, 0u, false, rd_is_new_scratch, dst_states,
																dst_cands, write_base, &write_local, cap_states, cap_cands);
					}
					break;
				}
			}
		}
	}

	return local_count;
}

__global__ void opt_count_kernel(const opt_state* __restrict__ src_front, u32 n_src,
																 opt_layer_ctx ctx, u32* __restrict__ d_counts) {
	const u32 tid = blockIdx.x * blockDim.x + threadIdx.x;
	if(tid >= n_src) { return; }

	const opt_state& src = src_front[tid];
	const u32 c = opt_expand_one<false>(ctx, src, nullptr, nullptr, 0, 0, 0);
	d_counts[tid] = c;
}

__global__ void opt_emit_kernel(const opt_state* __restrict__ src_front, u32 n_src,
																const u64* __restrict__ d_offsets, opt_layer_ctx ctx,
																opt_state* __restrict__ dst_states,
																opt_candidate* __restrict__ dst_cands, u64 cap_states,
																u64 cap_cands) {
	const u32 tid = blockIdx.x * blockDim.x + threadIdx.x;
	if(tid >= n_src) { return; }

	const opt_state src = src_front[tid];
	const u64 base = d_offsets[tid];
	opt_expand_one<true>(ctx, src, dst_states, dst_cands, base, cap_states, cap_cands);
}

i32 opt_enum_context_make(opt_enum_context* ec, u64 batch_size) {
	*ec = {};

	dmalloc(&ec->d_meta, (u64)OP_COUNT * sizeof(opt_op_meta), "enum_ctx d_meta");
	dmalloc(&ec->d_imms, (u64)64 * sizeof(i64), "enum_ctx d_imms");
	ec->n_meta = 0;
	ec->n_imms_cap = 64;

	u64 capacity = batch_size;
	{
		u64 free_mem = 0;
		u64 total_mem = 0;
		cudaMemGetInfo(&free_mem, &total_mem);
		(void)total_mem;
		const u64 reserved = 128ULL * 1024ULL * 1024ULL;
		const u64 usable = free_mem > reserved ? (free_mem - reserved) : 0;
		const u64 per_slot =
			2ULL * sizeof(opt_state) + sizeof(u64) + sizeof(u32) + sizeof(opt_candidate);
		const u64 vram_capacity = usable / per_slot;
		if(vram_capacity < capacity) { capacity = vram_capacity; }
		if(capacity < 1024) { capacity = 1024; }
	}
	ec->capacity = capacity;

	dmalloc(&ec->d_front_a, capacity * sizeof(opt_state), "enum_ctx front_a");
	dmalloc(&ec->d_front_b, capacity * sizeof(opt_state), "enum_ctx front_b");
	dmalloc(&ec->d_counts, capacity * sizeof(u32), "enum_ctx d_counts");
	dmalloc(&ec->d_offsets, capacity * sizeof(u64), "enum_ctx d_offsets");
	dmalloc(&ec->d_out, capacity * sizeof(opt_candidate), "enum_ctx d_out");

	ec->scan_tmp_bytes = 0;
	cub::DeviceScan::ExclusiveSum(nullptr, ec->scan_tmp_bytes, (u32*)ec->d_counts,
																(u64*)ec->d_offsets, (i32)capacity);
	dmalloc(&ec->d_scan_tmp, ec->scan_tmp_bytes, "enum_ctx scan tmp");

	return 0;
}

void opt_enum_context_free(opt_enum_context* ec) {
	if(ec->d_scan_tmp) { cudaFree(ec->d_scan_tmp); }
	if(ec->d_out) { cudaFree(ec->d_out); }
	if(ec->d_offsets) { cudaFree(ec->d_offsets); }
	if(ec->d_counts) { cudaFree(ec->d_counts); }
	if(ec->d_front_b) { cudaFree(ec->d_front_b); }
	if(ec->d_front_a) { cudaFree(ec->d_front_a); }
	if(ec->d_imms) { cudaFree(ec->d_imms); }
	if(ec->d_meta) { cudaFree(ec->d_meta); }
	*ec = {};
}

void opt_enumerate(opt_enum_context* ec, const opt_enum_config* cfg, u64 cap,
									 opt_candidate** out_d_cands, u64* out_n_cands) {
	*out_d_cands = (opt_candidate*)ec->d_out;
	*out_n_cands = 0;

	if(cap == 0 || cfg->prog_len == 0) { return; }

	opt_op_meta h_meta[OP_COUNT];
	u32 n_meta = 0;
	opt_build_meta_host(cfg->pool, h_meta, &n_meta);
	if(n_meta == 0) { return; }

	const u64 live_in = cfg->live_in_mask & ~1ULL;
	const u64 preserved = live_in | cfg->live_out_mask;

	htod_memcpy(ec->d_meta, h_meta, n_meta * sizeof(opt_op_meta), "enum cp meta");
	htod_memcpy(ec->d_imms, cfg->imms->vals, cfg->imms->n * sizeof(i64), "enum cp imms");
	opt_op_meta* d_meta = (opt_op_meta*)ec->d_meta;
	i64* d_imms = (i64*)ec->d_imms;
	const u64 capacity = ec->capacity < cap ? ec->capacity : cap;

	opt_state* d_front_a = (opt_state*)ec->d_front_a;
	opt_state* d_front_b = (opt_state*)ec->d_front_b;
	u32* d_counts = (u32*)ec->d_counts;
	u64* d_offsets = (u64*)ec->d_offsets;
	opt_candidate* d_out = (opt_candidate*)ec->d_out;
	void* d_scan_tmp = ec->d_scan_tmp;
	size_t scan_tmp_bytes = ec->scan_tmp_bytes;

	opt_state h_root;
	for(u32 k = 0; k < SYNTH_PROG_LEN; ++k) {
		h_root.code[k] = {};
		h_root.code[k].op = OP_NOP;
	}
	h_root.demanded = cfg->live_out_mask;
	h_root.used_scratch = 0;
	h_root.idx = (i32)cfg->prog_len - 1;
	h_root._pad = 0;
	htod_memcpy(d_front_a, &h_root, sizeof(opt_state), "enum seed");
	u64 n_front = 1;

	u64 scratch_mask = 0;
	{
		const u32 hi = cfg->max_scratch < 32 ? cfg->max_scratch : 32;
		for(u32 r = 5; r < hi; ++r) {
			const u64 bit = 1ULL << r;
			if(!(preserved & bit)) { scratch_mask |= bit; }
		}
	}

	const b32 profile = getenv("SUP_PROFILE") != nullptr;
	cudaEvent_t ev_a = nullptr, ev_b = nullptr, ev_c = nullptr, ev_d = nullptr, ev_e = nullptr;
	if(profile) {
		cudaEventCreate(&ev_a);
		cudaEventCreate(&ev_b);
		cudaEventCreate(&ev_c);
		cudaEventCreate(&ev_d);
		cudaEventCreate(&ev_e);
	}

	u64 emitted_cands = 0;

	for(i32 layer = (i32)cfg->prog_len - 1; layer >= 0; --layer) {
		if(n_front == 0) { break; }
		u64 src_avail;
		if(layer == 0) {
			src_avail = live_in | 1ULL;
		} else {
			src_avail = live_in | 1ULL | scratch_mask | cfg->live_out_mask;
		}

		opt_layer_ctx ctx;
		ctx.meta = d_meta;
		ctx.n_meta = n_meta;
		ctx.imms = d_imms;
		ctx.n_imms = cfg->imms->n;
		ctx.live_in_mask = live_in;
		ctx.live_out_mask = cfg->live_out_mask;
		ctx.preserved_mask = preserved;
		ctx.src_avail = src_avail;
		ctx.scratch_mask = scratch_mask;
		ctx.max_scratch = cfg->max_scratch;
		ctx.is_last_layer = (layer == 0);

		const u32 threads = 256;
		const u32 blocks = (u32)((n_front + threads - 1) / threads);

		if(profile) { cudaEventRecord(ev_a); }
		opt_count_kernel<<<blocks, threads>>>(d_front_a, (u32)n_front, ctx, d_counts);
		check_cuda(cudaGetLastError(), "enum count kernel");
		if(profile) { cudaEventRecord(ev_b); }
		cub::DeviceScan::ExclusiveSum(d_scan_tmp, scan_tmp_bytes, d_counts, d_offsets, (i32)n_front);
		if(profile) { cudaEventRecord(ev_c); }

		u64 last_off = 0;
		u32 last_cnt = 0;
		dtoh_memcpy(&last_off, d_offsets + (n_front - 1), sizeof(u64), "enum offsets[-1]");
		dtoh_memcpy(&last_cnt, d_counts + (n_front - 1), sizeof(u32), "enum counts[-1]");
		const u64 total = last_off + (u64)last_cnt;

		if(profile) { cudaEventRecord(ev_d); }

		if(total > 0) {
			const u64 cap_states = ctx.is_last_layer ? 0 : capacity;
			const u64 cap_cands = ctx.is_last_layer ? (capacity - emitted_cands) : 0;

			opt_state* dst_states = ctx.is_last_layer ? nullptr : d_front_b;
			opt_candidate* dst_cands = ctx.is_last_layer ? (d_out + emitted_cands) : nullptr;
			opt_emit_kernel<<<blocks, threads>>>(d_front_a, (u32)n_front, d_offsets, ctx, dst_states,
																					 dst_cands, cap_states, cap_cands);
			check_cuda(cudaGetLastError(), "enum emit kernel");
		}

		if(profile) {
			cudaEventRecord(ev_e);
			cudaEventSynchronize(ev_e);
			f32 t_count = 0, t_scan = 0, t_sync = 0, t_emit = 0;
			cudaEventElapsedTime(&t_count, ev_a, ev_b);
			cudaEventElapsedTime(&t_scan, ev_b, ev_c);
			cudaEventElapsedTime(&t_sync, ev_c, ev_d);
			cudaEventElapsedTime(&t_emit, ev_d, ev_e);
			fprintf(stderr,
							"[enum] layer=%d n_front=%zu total=%zu count=%.2fms scan=%.2fms "
							"sync=%.2fms emit=%.2fms\n",
							layer, (size_t)n_front, (size_t)total, t_count, t_scan, t_sync, t_emit);
		}

		if(ctx.is_last_layer) {
			const u64 remaining = capacity - emitted_cands;
			const u64 written = total < remaining ? total : remaining;
			emitted_cands += written;
			n_front = 0;
		} else {
			n_front = total < capacity ? total : capacity;
			opt_state* tmp = d_front_a;
			d_front_a = d_front_b;
			d_front_b = tmp;
		}
	}

	if(profile) {
		cudaEventDestroy(ev_a);
		cudaEventDestroy(ev_b);
		cudaEventDestroy(ev_c);
		cudaEventDestroy(ev_d);
		cudaEventDestroy(ev_e);
	}

	if(emitted_cands > 0) { check_cuda(cudaDeviceSynchronize(), "enum sync"); }
	*out_d_cands = d_out;
	*out_n_cands = emitted_cands;
}
