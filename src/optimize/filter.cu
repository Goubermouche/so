#include "optimize/filter.cuh"

static __constant__ U8 c_slot_idx[32];
static __constant__ U8 c_unpack[FilterMaxActiveRegs];

static U8 h_slot_idx[32];
static U8 h_unpack[FilterMaxActiveRegs];
static U64 h_last_active_mask = 0;
static __constant__ U16 cf_meta_op[EnumMaxMeta];
static __constant__ I64 cf_imms[EnumImmPoolSize];

U32 filter_upload_slot_idx(U64 active_mask) {
	active_mask |= 1ull;
	if(active_mask == h_last_active_mask) {
		U32 k = 0;
		for(U32 r = 0; r < 32; ++r) {
			if(active_mask & (1ull << r)) ++k;
		}
		return k;
	}
	for(U32 r = 0; r < 32; ++r) { h_slot_idx[r] = 0xFF; }
	for(U32 s = 0; s < FilterMaxActiveRegs; ++s) { h_unpack[s] = 0; }
	h_slot_idx[0] = 0;
	h_unpack[0] = 0;
	U32 k = 1;
	for(U32 r = 1; r < 32; ++r) {
		if(!(active_mask & (1ull << r))) continue;
		if(k >= FilterMaxActiveRegs) return 0;
		h_slot_idx[r] = (U8)k;
		h_unpack[k] = (U8)r;
		++k;
	}
	U8 device_slot_idx[32];
	for(U32 r = 0; r < 32; ++r) {
		device_slot_idx[r] = (h_slot_idx[r] == 0xFF) ? (U8)0 : h_slot_idx[r];
	}
	cudaMemcpyToSymbol(c_slot_idx, device_slot_idx, sizeof(device_slot_idx));
	cudaMemcpyToSymbol(c_unpack, h_unpack, sizeof(h_unpack));
	h_last_active_mask = active_mask;
	return k;
}

U64 filter_pack_mask(U64 raw_mask) {
	U64 out = 0;
	for(U32 r = 0; r < 32; ++r) {
		if(!(raw_mask & (1ull << r))) continue;
		const U8 s = h_slot_idx[r];
		if(s == 0xFF) continue;
		out |= 1ull << s;
	}
	return out;
}

// TODO: unify w tester/cleanup
typedef struct __align__(16) DecodedInst {
	U32 op;
	U8 rd;
	U8 rs1;
	U8 rs2;
	U8 _pad;
	U64 imm;
} DecodedInst;

static __constant__ U16 c_decode_info[InstructionOpcode_Count];
static U16 h_decode_info[InstructionOpcode_Count];
static B32 h_decode_info_initialised = false;

void filter_init_decode_info() {
	if(h_decode_info_initialised) return;
	for(U32 op = 0; op < (U32)InstructionOpcode_Count; ++op) {
		const InstructionInfo* info = &instruction_db_host.row[op];
		U32 reg_mask = 0;
		if(info->dst_slot >= 0) reg_mask |= 1u << (U32)info->dst_slot;
		if(info->src_slot >= 0) reg_mask |= 1u << (U32)info->src_slot;
		if(info->src2_slot >= 0) reg_mask |= 1u << (U32)info->src2_slot;
		U32 imm_slot = 0xF;
		for(U32 k = 0; k < 4; ++k) {
			if(info->operands[k] == InstructionOperandType_Imm) {
				imm_slot = k;
				break;
			}
		}
		h_decode_info[op] = (U16)((reg_mask & 0xF) | (imm_slot << 8));
	}
	cudaMemcpyToSymbol(c_decode_info, h_decode_info, sizeof(h_decode_info));
	h_decode_info_initialised = true;
}

void filter_upload_meta(const EnumMeta* h_meta, U32 n_meta, const I64* h_imms, U32 n_imms) {
	U16 ops_buf[EnumMaxMeta];
	for(U32 i = 0; i < n_meta && i < EnumMaxMeta; ++i) { ops_buf[i] = h_meta[i].op; }
	cudaMemcpyToSymbol(cf_meta_op, ops_buf, n_meta * sizeof(U16));
	cudaMemcpyToSymbol(cf_imms, h_imms, n_imms * sizeof(I64));
}

__device__ __forceinline__ DecodedInst filter_decode_one(const Instruction& in) {
	DecodedInst d;
	const U32 op = (U32)in.op;
	d.op = op;
	d._pad = 0;
	if(op == (U32)InstructionOpcode_Nop || op >= (U32)InstructionOpcode_Count) {
		d.rd = 0;
		d.rs1 = 0;
		d.rs2 = 0;
		d.imm = 0;
		return d;
	}
	const U32 info = (U32)c_decode_info[op];
	const U32 reg_mask = info & 0xF;
	const U32 imm_slot = (info >> 8) & 0xF;
	d.rd = c_slot_idx[(U32)in.operands[0].reg & 31];
	d.rs1 = (reg_mask & 0x2) ? c_slot_idx[(U32)in.operands[1].reg & 31] : (U8)0;
	d.rs2 = (reg_mask & 0x4) ? c_slot_idx[(U32)in.operands[2].reg & 31] : (U8)0;
	d.imm = (imm_slot < 4) ? in.operands[imm_slot].imm : (U64)0;
	return d;
}

__device__ __forceinline__ void sim_step(U64* regs, const DecodedInst* d) {
	const U32 op = d->op;
	const U32 rd = (U32)d->rd;
	const U64 a = regs[(U32)d->rs1];
	const U64 b = regs[(U32)d->rs2];
	const U64 imm = d->imm;

	// TODO: extensions
	U64 v;
	switch(op) {
		case InstructionOpcode_Add: v = a + b; break;
		case InstructionOpcode_Sub: v = a - b; break;
		case InstructionOpcode_Sll: v = a << (b & 0x3F); break;
		case InstructionOpcode_Slt: v = ((I64)a < (I64)b) ? 1ull : 0ull; break;
		case InstructionOpcode_Sltu: v = (a < b) ? 1ull : 0ull; break;
		case InstructionOpcode_Xor: v = a ^ b; break;
		case InstructionOpcode_Srl: v = a >> (b & 0x3F); break;
		case InstructionOpcode_Sra: v = (U64)((I64)a >> (b & 0x3F)); break;
		case InstructionOpcode_Or: v = a | b; break;
		case InstructionOpcode_And: v = a & b; break;
		case InstructionOpcode_Addi: v = a + imm; break;
		case InstructionOpcode_Slti: v = ((I64)a < (I64)imm) ? 1ull : 0ull; break;
		case InstructionOpcode_Sltiu: v = (a < imm) ? 1ull : 0ull; break;
		case InstructionOpcode_Xori: v = a ^ imm; break;
		case InstructionOpcode_Ori: v = a | imm; break;
		case InstructionOpcode_Andi: v = a & imm; break;
		case InstructionOpcode_Slli: v = a << (imm & 0x3F); break;
		case InstructionOpcode_Srli: v = a >> (imm & 0x3F); break;
		case InstructionOpcode_Srai: v = (U64)((I64)a >> (imm & 0x3F)); break;
		case InstructionOpcode_Lui: v = (U64)(I64)(I32)((U32)imm << 12); break;
		case InstructionOpcode_Addiw: v = (U64)(I64)(I32)((U32)a + (U32)imm); break;
		case InstructionOpcode_Slliw: v = (U64)(I64)(I32)((U32)a << (imm & 0x1F)); break;
		case InstructionOpcode_Srliw: v = (U64)(I64)(I32)((U32)a >> (imm & 0x1F)); break;
		case InstructionOpcode_Sraiw: v = (U64)(I64)((I32)a >> (imm & 0x1F)); break;
		case InstructionOpcode_Addw: v = (U64)(I64)(I32)((U32)a + (U32)b); break;
		case InstructionOpcode_Subw: v = (U64)(I64)(I32)((U32)a - (U32)b); break;
		case InstructionOpcode_Sllw: v = (U64)(I64)(I32)((U32)a << (b & 0x1F)); break;
		case InstructionOpcode_Srlw: v = (U64)(I64)(I32)((U32)a >> (b & 0x1F)); break;
		case InstructionOpcode_Sraw: v = (U64)(I64)((I32)a >> (b & 0x1F)); break;
		case InstructionOpcode_Mul: v = a * b; break;
		case InstructionOpcode_Mulh: {
			const __int128 sa = (__int128)(I64)a;
			const __int128 sb = (__int128)(I64)b;
			v = (U64)(I64)((sa * sb) >> 64);
		} break;
		case InstructionOpcode_Mulhsu: {
			const __int128 sa = (__int128)(I64)a;
			const __int128 ub = (__int128)(unsigned __int128)b;
			v = (U64)(I64)((sa * ub) >> 64);
		} break;
		case InstructionOpcode_Mulhu: {
			const unsigned __int128 ua = (unsigned __int128)a;
			const unsigned __int128 ub = (unsigned __int128)b;
			v = (U64)((ua * ub) >> 64);
		} break;
		case InstructionOpcode_Div: {
			const I64 sa = (I64)a;
			const I64 sb = (I64)b;
			I64 q;
			if(sb == 0)
				q = -1;
			else if(sa == (I64)0x8000000000000000ULL && sb == -1)
				q = sa;
			else
				q = sa / sb;
			v = (U64)q;
		} break;
		case InstructionOpcode_Divu: v = (b == 0) ? (U64)-1 : (a / b); break;
		case InstructionOpcode_Rem: {
			const I64 sa = (I64)a;
			const I64 sb = (I64)b;
			I64 r;
			if(sb == 0)
				r = sa;
			else if(sa == (I64)0x8000000000000000ULL && sb == -1)
				r = 0;
			else
				r = sa % sb;
			v = (U64)r;
		} break;
		case InstructionOpcode_Remu: v = (b == 0) ? a : (a % b); break;
		case InstructionOpcode_Mulw: {
			const I32 r = (I32)a * (I32)b;
			v = (U64)(I64)r;
		} break;
		case InstructionOpcode_Divw: {
			const I32 sa = (I32)a;
			const I32 sb = (I32)b;
			I32 r;
			if(sb == 0)
				r = -1;
			else if(sa == (I32)0x80000000 && sb == -1)
				r = sa;
			else
				r = sa / sb;
			v = (U64)(I64)r;
		} break;
		case InstructionOpcode_Divuw: {
			const U32 ua = (U32)a;
			const U32 ub = (U32)b;
			v = (U64)(I64)(I32)(ub == 0 ? (U32)-1 : ua / ub);
		} break;
		case InstructionOpcode_Remw: {
			const I32 sa = (I32)a;
			const I32 sb = (I32)b;
			I32 r;
			if(sb == 0)
				r = sa;
			else if(sa == (I32)0x80000000 && sb == -1)
				r = 0;
			else
				r = sa % sb;
			v = (U64)(I64)r;
		} break;
		case InstructionOpcode_Remuw: {
			const U32 ua = (U32)a;
			const U32 ub = (U32)b;
			v = (U64)(I64)(I32)(ub == 0 ? ua : ua % ub);
		} break;
		default: return;
	}

	if(rd != 0) regs[rd] = v;
}

extern __shared__ U8 g_smem[];

__global__ __launch_bounds__(FilterSimThreadsPerBlock, 8) void opt_filter_kernel(
	const U64* __restrict__ tuples,
	const EnumStateCode* __restrict__ parent_code,
	U8* __restrict__ pass_count,
	U64 n_candidates,
	U64 packed_live_mask,
	U32 prog_len,
	U32 active_count,
	const CpuState* __restrict__ test_in,
	const CpuState* __restrict__ target_out
) {
	const U32 tid = threadIdx.x;
	const U64 cand_id = (U64)blockIdx.x * FilterSimThreadsPerBlock + tid;

	U64* s_test_in = (U64*)g_smem;
	U64* s_target_out = s_test_in + (size_t)FilterTestCount * active_count;

	// load packed
	{
		const U32 total = FilterTestCount * active_count;
		for(U32 i = tid; i < total; i += FilterSimThreadsPerBlock) {
			// derive (t, ps)
			U32 t, ps;
			if(active_count != 0) {
				t = i / active_count;
				ps = i - t * active_count;
			} else {
				t = 0;
				ps = 0;
			}
			const U32 raw_r = (U32)c_unpack[ps];
			s_test_in[(size_t)t * active_count + ps] = test_in[t].regs[raw_r];
			s_target_out[(size_t)t * active_count + ps] = target_out[t].regs[raw_r];
		}
	}
	__syncthreads();

	// decode tuple, fetch parent code, build slot-0 DecodedInst, decode rest
	DecodedInst prog[MaxProgramLen];
	{
		U64 t = 0;
		U32 parent_local_id = 0;
		U32 op_idx = 0;
		U32 rd_raw = 0;
		U32 rs1_raw = 0;
		U32 rs2_or_imm_idx = 0;
		B32 is_imm = false;
		if(cand_id < n_candidates) {
			t = tuples[cand_id];
			parent_local_id = (U32)(t & 0xFFFFFFFFull);
			op_idx = (U32)((t >> 32) & 0xFFull);
			rd_raw = (U32)((t >> 40) & 0x1Full);
			rs1_raw = (U32)((t >> 45) & 0x1Full);
			rs2_or_imm_idx = (U32)((t >> 50) & 0xFFull);
			is_imm = (B32)((t >> 58) & 0x1ull);
		}

		// slot 0: build decoded directly
		const U32 op = (cand_id < n_candidates) ? (U32)cf_meta_op[op_idx] : (U32)InstructionOpcode_Nop;
		DecodedInst built;
		built.op = op;
		built._pad = 0;
		built.rd = c_slot_idx[rd_raw & 31];
		if(is_imm) {
			built.rs1 = c_slot_idx[rs1_raw & 31];
			built.rs2 = 0;
			built.imm = (U64)cf_imms[rs2_or_imm_idx];
		} else {
			built.rs1 = c_slot_idx[rs1_raw & 31];
			built.rs2 = c_slot_idx[rs2_or_imm_idx & 31];
			built.imm = 0;
		}
		prog[0] = built;

		// slots 1..prog_len-1: pull from parent code via the cache
		// slots >= prog_len: NOP
#pragma unroll
		for(U32 k = 1; k < MaxProgramLen; ++k) {
			Instruction raw;
			if(cand_id < n_candidates && k < prog_len) {
				raw = parent_code[parent_local_id].code[k];
			} else {
				raw.op = InstructionOpcode_Nop;
				// compare our results to the reference
#pragma unroll
				for(U32 j = 0; j < 4; ++j) { raw.operands[j].imm = 0; }
			}
			prog[k] = filter_decode_one(raw);
		}
	}

	if(cand_id >= n_candidates) return;

	// run tests
	U32 pass_mask = 0;
	B32 lane_alive = true;

	for(U32 t = 0; t < FilterTestCount; ++t) {
		B32 ok = false;
		if(lane_alive) {
			U64 regs[FilterMaxActiveRegs];

			for(U32 i = 0; i < active_count; ++i) { regs[i] = s_test_in[(size_t)t * active_count + i]; }
			regs[0] = 0;

			for(U32 i = 0; i < prog_len; ++i) { sim_step(regs, &prog[i]); }

			// compare against broadcast
			ok = true;
			U64 m = packed_live_mask;
			while(m) {
				const U32 r = __ffsll((long long)m) - 1;
				m &= m - 1;
				const U64 expected = s_target_out[(size_t)t * active_count + r];
				if(regs[r] != expected) {
					ok = false;
					break;
				}
			}
		}

		if(ok) {
			pass_mask |= (1u << t);
		} else {
			lane_alive = false;
		}

		// if every lane has failed, break
		if(!__any_sync(0xFFFFFFFFu, lane_alive)) break;
	}

	// pass results
	const B32 all_passed = (pass_mask == 0xFFFFFFFFu);
	pass_count[cand_id] = all_passed ? (U8)FilterTestCount : (U8)0;
}

I32 filter_make(Filter* filter, U64 max_chunk_cands) {
	filter->max_chunk_cands = 0;
	filter->d_test_in = 0;
	filter->d_target_out = 0;
	filter->d_pass_count = 0;
	filter->h_pass_count = 0;
	filter->h_pass_count_cap = 0;
	filter->tests_dirty = true;

	filter_init_decode_info();

	I32 dev = 0;
	if(cudaGetDevice(&dev) != cudaSuccess) return 1;
	cudaDeviceProp p;
	if(cudaGetDeviceProperties(&p, dev) != cudaSuccess) return 2;

	U64 free_mem = 0, total_mem = 0;
	if(cudaMemGetInfo(&free_mem, &total_mem) != cudaSuccess) return 3;
	U64 usable_mem = (U64)((F64)free_mem * 0.30);
	const U64 fixed_mem_bytes = 2ull * FilterTestCount * sizeof(CpuState);
	if(usable_mem <= fixed_mem_bytes) {
		fprintf(stderr, "error: insufficient VRAM for fixed buffers\n");
		return 4;
	}
	usable_mem -= fixed_mem_bytes;

	const U64 per_cand = sizeof(U8) + 2 * sizeof(U32);
	U64 chunk = usable_mem / per_cand;
	const U64 hw_warps = (U64)p.multiProcessorCount * p.maxThreadsPerMultiProcessor / 32ull;
	const U64 ideal_lower = hw_warps * 8ull;
	if(chunk < ideal_lower) chunk = ideal_lower;
	if(chunk < 1024) chunk = 1024;
	if(max_chunk_cands != 0 && max_chunk_cands < chunk) chunk = max_chunk_cands;
	const U64 cpb = FilterCandsPerBlock;
	// align to warp block boundaries
	const U64 padded_chunk = chunk + cpb - 1;
	chunk = (padded_chunk / cpb) * cpb;
	filter->max_chunk_cands = chunk;

	// allocate persistent buffers
	dmalloc(&filter->d_test_in, FilterTestCount * sizeof(CpuState));
	dmalloc(&filter->d_target_out, FilterTestCount * sizeof(CpuState));
	dmalloc(&filter->d_pass_count, filter->max_chunk_cands * sizeof(U8));

	// pinned host buffer for pass_count copyback, reused across all chunks
	filter->h_pass_count_cap = filter->max_chunk_cands;
	if(cudaMallocHost((void**)&filter->h_pass_count, filter->h_pass_count_cap * sizeof(U8)) !=
		 cudaSuccess) {
		filter->h_pass_count = (U8*)malloc(filter->h_pass_count_cap * sizeof(U8));
		if(!filter->h_pass_count) return 5;
	}

	const U64 used_mem = fixed_mem_bytes + filter->max_chunk_cands * sizeof(U8);

	printf("filter:\n");
	printf("  chunk size: %zu cands\n", filter->max_chunk_cands);
	printf("  VRAM: %zuMB / %zuMB avail\n", used_mem / MB(1), free_mem / MB(1));

	return 0;
}

void filter_free(Filter* filter) {
	if(filter->d_test_in) cudaFree(filter->d_test_in);
	if(filter->d_target_out) cudaFree(filter->d_target_out);
	if(filter->d_pass_count) cudaFree(filter->d_pass_count);
	if(filter->h_pass_count) {
		if(cudaFreeHost(filter->h_pass_count) != cudaSuccess) free(filter->h_pass_count);
	}
}

void filter_mark_tests_dirty(Filter* filter) { filter->tests_dirty = true; }

void filter_run(Filter* filter, FilterOptions* opt, U8** out_pass_counts) {
	*out_pass_counts = filter->h_pass_count;
	if(opt->tuples == 0 || opt->n_candidates == 0) return;

	const U32 active_count = filter_upload_slot_idx(opt->active_mask);
	if(active_count == 0 || active_count > FilterMaxActiveRegs) {
		fprintf(
			stderr,
			"error: active register set exceeds FilterMaxActiveRegs=%d (got %u)\n",
			FilterMaxActiveRegs,
			active_count
		);
		return;
	}
	const U64 packed_live_mask = filter_pack_mask(opt->live_mask);

	if(filter->tests_dirty) {
		const U64 test_size = FilterTestCount * sizeof(CpuState);
		htod_memcpy(filter->d_test_in, opt->test_in, test_size);
		htod_memcpy(filter->d_target_out, opt->target_out, test_size);
		filter->tests_dirty = false;
	}

	const U32 shmem_bytes = (U32)(2ull * FilterTestCount * active_count * sizeof(U64));
	U64 done = 0;

	while(done < opt->n_candidates) {
		U64 this_chunk = (opt->n_candidates - done < filter->max_chunk_cands)
											 ? (opt->n_candidates - done)
											 : filter->max_chunk_cands;

		const U32 n_blocks =
			(U32)((this_chunk + FilterSimThreadsPerBlock - 1) / FilterSimThreadsPerBlock);
		dim3 grid(n_blocks);
		dim3 block(FilterSimThreadsPerBlock);
		opt_filter_kernel<<<grid, block, shmem_bytes>>>(
			opt->tuples + done,
			opt->parent_code,
			(U8*)filter->d_pass_count,
			this_chunk,
			packed_live_mask,
			opt->prog_len,
			active_count,
			(const CpuState*)filter->d_test_in,
			(const CpuState*)filter->d_target_out
		);
		check_cuda(cudaGetLastError(), "filter kernel launch");
		dtoh_memcpy(filter->h_pass_count + done, filter->d_pass_count, this_chunk * sizeof(U8));
		done += this_chunk;
	}
}
