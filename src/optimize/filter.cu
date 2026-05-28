#include "optimize/filter.cuh"

static __constant__ U8 c_slot_idx[32];
static __constant__ U8 c_unpack[FilterMaxActiveRegs];

static U8 h_slot_idx[32];
static U8 h_unpack[FilterMaxActiveRegs];
static U64 h_last_active_mask = 0;
static __constant__ U16 cf_meta_op[EnumMaxMeta];
static __constant__ U8 cf_meta_cls[EnumMaxMeta];
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
		U8 s = h_slot_idx[r];
		if(s == 0xFF) continue;
		out |= 1ull << s;
	}
	return out;
}

static __constant__ U16 c_decode_info[InstructionOpcode_Count];
static U16 h_decode_info[InstructionOpcode_Count];

// 0 = cheap, 1 = mul, 2 = div
static __constant__ U8 c_op_class[InstructionOpcode_Count];
static U8 h_op_class[InstructionOpcode_Count];

static B32 h_decode_info_initialised = false;

void filter_init_decode_info() {
	if(h_decode_info_initialised) return;
	for(U32 op = 0; op < (U32)InstructionOpcode_Count; ++op) {
		InstructionInfo* info = &instruction_db_host.row[op];
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

		U8 cls = 0;
		switch(op) {
			case InstructionOpcode_Mul:
			case InstructionOpcode_Mulh:
			case InstructionOpcode_Mulhsu:
			case InstructionOpcode_Mulhu:
			case InstructionOpcode_Mulw: cls = 1; break;
			case InstructionOpcode_Div:
			case InstructionOpcode_Divu:
			case InstructionOpcode_Rem:
			case InstructionOpcode_Remu:
			case InstructionOpcode_Divw:
			case InstructionOpcode_Divuw:
			case InstructionOpcode_Remw:
			case InstructionOpcode_Remuw: cls = 2; break;
			default: break;
		}
		h_op_class[op] = cls;

		h_decode_info[op] = (U16)((reg_mask & 0xF) | (imm_slot << 8) | ((U32)cls << 12));
	}

	cudaMemcpyToSymbol(c_decode_info, h_decode_info, sizeof(h_decode_info));
	cudaMemcpyToSymbol(c_op_class, h_op_class, sizeof(h_op_class));
	h_decode_info_initialised = true;
}

void filter_upload_meta(EnumMeta* h_meta, U32 n_meta, I64* h_imms, U32 n_imms) {
	U16 ops_buf[EnumMaxMeta];
	U8 cls_buf[EnumMaxMeta];
	for(U32 i = 0; i < n_meta && i < EnumMaxMeta; ++i) {
		ops_buf[i] = h_meta[i].op;
		cls_buf[i] = h_op_class[h_meta[i].op];
	}
	cudaMemcpyToSymbol(cf_meta_op, ops_buf, n_meta * sizeof(U16));
	cudaMemcpyToSymbol(cf_meta_cls, cls_buf, n_meta * sizeof(U8));
	cudaMemcpyToSymbol(cf_imms, h_imms, n_imms * sizeof(I64));
}

__device__ __forceinline__ U64 sim_cheap(U32 op, U64 a, U64 b, U64 imm) {
	U32 sh_b = (U32)(b & 0x3F);
	U32 sh_i = (U32)(imm & 0x3F);
	U32 sh_b5 = (U32)(b & 0x1F);
	U32 sh_i5 = (U32)(imm & 0x1F);
	U32 a32 = (U32)a;
	U32 b32 = (U32)b;
	U32 i32 = (U32)imm;

	switch(op) {
		case InstructionOpcode_Add: return a + b;
		case InstructionOpcode_Sub: return a - b;
		case InstructionOpcode_Sll: return a << sh_b;
		case InstructionOpcode_Slt: return ((I64)a < (I64)b) ? 1ull : 0ull;
		case InstructionOpcode_Sltu: return (a < b) ? 1ull : 0ull;
		case InstructionOpcode_Xor: return a ^ b;
		case InstructionOpcode_Srl: return a >> sh_b;
		case InstructionOpcode_Sra: return (U64)((I64)a >> sh_b);
		case InstructionOpcode_Or: return a | b;
		case InstructionOpcode_And: return a & b;
		case InstructionOpcode_Addi: return a + imm;
		case InstructionOpcode_Slti: return ((I64)a < (I64)imm) ? 1ull : 0ull;
		case InstructionOpcode_Sltiu: return (a < imm) ? 1ull : 0ull;
		case InstructionOpcode_Xori: return a ^ imm;
		case InstructionOpcode_Ori: return a | imm;
		case InstructionOpcode_Andi: return a & imm;
		case InstructionOpcode_Slli: return a << sh_i;
		case InstructionOpcode_Srli: return a >> sh_i;
		case InstructionOpcode_Srai: return (U64)((I64)a >> sh_i);
		case InstructionOpcode_Lui: return (U64)(I64)(I32)((U32)imm << 12);
		case InstructionOpcode_Addiw: return (U64)(I64)(I32)(a32 + i32);
		case InstructionOpcode_Slliw: return (U64)(I64)(I32)(a32 << sh_i5);
		case InstructionOpcode_Srliw: return (U64)(I64)(I32)(a32 >> sh_i5);
		case InstructionOpcode_Sraiw: return (U64)(I64)((I32)a32 >> sh_i5);
		case InstructionOpcode_Addw: return (U64)(I64)(I32)(a32 + b32);
		case InstructionOpcode_Subw: return (U64)(I64)(I32)(a32 - b32);
		case InstructionOpcode_Sllw: return (U64)(I64)(I32)(a32 << sh_b5);
		case InstructionOpcode_Srlw: return (U64)(I64)(I32)(a32 >> sh_b5);
		case InstructionOpcode_Sraw: return (U64)(I64)((I32)a32 >> sh_b5);
		default: return 0;
	}
}

__device__ __forceinline__ U64 sim_mul(U32 op, U64 a, U64 b) {
	switch(op) {
		case InstructionOpcode_Mul: return a * b;
		case InstructionOpcode_Mulh: {
			__int128 sa = (__int128)(I64)a;
			__int128 sb = (__int128)(I64)b;
			return (U64)(I64)((sa * sb) >> 64);
		}
		case InstructionOpcode_Mulhsu: {
			__int128 sa = (__int128)(I64)a;
			__int128 ub = (__int128)(unsigned __int128)b;
			return (U64)(I64)((sa * ub) >> 64);
		}
		case InstructionOpcode_Mulhu: {
			unsigned __int128 ua = (unsigned __int128)a;
			unsigned __int128 ub = (unsigned __int128)b;
			return (U64)((ua * ub) >> 64);
		}
		case InstructionOpcode_Mulw: {
			I32 r = (I32)a * (I32)b;
			return (U64)(I64)r;
		}
		default: return 0;
	}
}

__device__ __forceinline__ U64 sim_div(U32 op, U64 a, U64 b) {
	switch(op) {
		case InstructionOpcode_Div: {
			I64 sa = (I64)a, sb = (I64)b;
			if(sb == 0) return (U64)(I64)-1;
			if(sa == (I64)0x8000000000000000ULL && sb == -1) return (U64)sa;
			return (U64)(sa / sb);
		}
		case InstructionOpcode_Divu: return (b == 0) ? (U64)-1 : (a / b);
		case InstructionOpcode_Rem: {
			I64 sa = (I64)a, sb = (I64)b;
			if(sb == 0) return (U64)sa;
			if(sa == (I64)0x8000000000000000ULL && sb == -1) return 0;
			return (U64)(sa % sb);
		}
		case InstructionOpcode_Remu: return (b == 0) ? a : (a % b);
		case InstructionOpcode_Divw: {
			I32 sa = (I32)a, sb = (I32)b;
			I32 r;
			if(sb == 0)
				r = -1;
			else if(sa == (I32)0x80000000 && sb == -1)
				r = sa;
			else
				r = sa / sb;
			return (U64)(I64)r;
		}
		case InstructionOpcode_Divuw: {
			U32 ua = (U32)a, ub = (U32)b;
			return (U64)(I64)(I32)(ub == 0 ? (U32)-1 : ua / ub);
		}
		case InstructionOpcode_Remw: {
			I32 sa = (I32)a, sb = (I32)b;
			I32 r;
			if(sb == 0)
				r = sa;
			else if(sa == (I32)0x80000000 && sb == -1)
				r = 0;
			else
				r = sa % sb;
			return (U64)(I64)r;
		}
		case InstructionOpcode_Remuw: {
			U32 ua = (U32)a, ub = (U32)b;
			return (U64)(I64)(I32)(ub == 0 ? ua : ua % ub);
		}
		default: return 0;
	}
}

__device__ __forceinline__ U64
sim_dispatch(U32 op, U64 a, U64 b, U64 imm, U32 cls, B32 warp_has_mul, B32 warp_has_div) {
	if(warp_has_mul && cls == 1u) return sim_mul(op, a, b);
	if(warp_has_div && cls == 2u) return sim_div(op, a, b);
	return sim_cheap(op, a, b, imm);
}

extern __shared__ U8 g_smem[];

template<U32 PROG_LEN>
__global__ __launch_bounds__(FilterSimThreadsPerBlock, 2) void opt_filter_kernel(
	U64* __restrict__ tuples,
	EnumStateCode* __restrict__ parent_code,
	U8* __restrict__ pass_count,
	U64 n_candidates,
	U64 packed_live_mask,
	U64 packed_live_in_mask,
	U32 active_count,
	CpuState* __restrict__ test_in,
	CpuState* __restrict__ target_out
) {
	U32 tid = threadIdx.x;
	U32 blk_n = blockDim.x;
	U64 cand_id = (U64)blockIdx.x * blk_n + tid;

	U64* s_test_in = (U64*)g_smem;
	U64* s_target_out = s_test_in + (size_t)FilterTestCount * active_count;
	U64* s_regs = s_target_out + (size_t)FilterTestCount * active_count;

	// test load
	{
		U32 ac = active_count;
		U32 total = FilterTestCount * ac;
		for(U32 i = tid; i < total; i += blk_n) {
			U32 t = i / ac;
			U32 r = i - t * ac;
			U32 raw_r = (U32)c_unpack[r];
			s_test_in[i] = test_in[t].regs[raw_r];
			s_target_out[i] = target_out[t].regs[raw_r];
		}
	}
	__syncthreads();

	// decode program
	U32 op_0 = 0, op_1 = 0, op_2 = 0, op_3 = 0, op_4 = 0, op_5 = 0, op_6 = 0, op_7 = 0;
	U32 rd_0 = 0, rd_1 = 0, rd_2 = 0, rd_3 = 0, rd_4 = 0, rd_5 = 0, rd_6 = 0, rd_7 = 0;
	U32 rs1_0 = 0, rs1_1 = 0, rs1_2 = 0, rs1_3 = 0, rs1_4 = 0, rs1_5 = 0, rs1_6 = 0, rs1_7 = 0;
	U32 rs2_0 = 0, rs2_1 = 0, rs2_2 = 0, rs2_3 = 0, rs2_4 = 0, rs2_5 = 0, rs2_6 = 0, rs2_7 = 0;
	U64 imm_0 = 0, imm_1 = 0, imm_2 = 0, imm_3 = 0, imm_4 = 0, imm_5 = 0, imm_6 = 0, imm_7 = 0;
	U32 cls_packed = 0;
	U32 op_class_or = 0;

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

		// slot 0
		op_0 = (cand_id < n_candidates) ? (U32)cf_meta_op[op_idx] : (U32)InstructionOpcode_Nop;
		rd_0 = (U32)c_slot_idx[rd_raw & 31];
		rs1_0 = (U32)c_slot_idx[rs1_raw & 31];
		if(is_imm) {
			rs2_0 = 0;
			imm_0 = (U64)cf_imms[rs2_or_imm_idx];
		} else {
			rs2_0 = (U32)c_slot_idx[rs2_or_imm_idx & 31];
			imm_0 = 0;
		}
		U32 cls0 = (cand_id < n_candidates) ? (U32)cf_meta_cls[op_idx] : 0u;
		cls_packed |= (cls0 & 0x3u);
		op_class_or |= cls0;

// slots 1..prog_len-1: decode parent_code instructions
#define DECODE_SLOT(K)                                                                             \
	do {                                                                                             \
		U32 op_ = InstructionOpcode_Nop;                                                               \
		U32 rd_ = 0, rs1_ = 0, rs2_ = 0;                                                               \
		U64 imm_ = 0;                                                                                  \
		U32 cls_K = 0;                                                                                 \
		if(cand_id < n_candidates && (K) < PROG_LEN) {                                                 \
			Instruction* in_ = &parent_code[parent_local_id].code[K];                                    \
			op_ = (U32)in_->op;                                                                          \
			U32 info_ = (U32)c_decode_info[op_];                                                         \
			U32 rmask_ = info_ & 0xF;                                                                    \
			U32 islot_ = (info_ >> 8) & 0xF;                                                             \
			cls_K = (info_ >> 12) & 0x3;                                                                 \
			rd_ = c_slot_idx[(U32)in_->operands[0].reg & 31];                                            \
			rs1_ = (rmask_ & 0x2) ? (U32)c_slot_idx[(U32)in_->operands[1].reg & 31] : 0u;                \
			rs2_ = (rmask_ & 0x4) ? (U32)c_slot_idx[(U32)in_->operands[2].reg & 31] : 0u;                \
			imm_ = (islot_ < 4) ? in_->operands[islot_].imm : 0ull;                                      \
		}                                                                                              \
		op_##K = op_;                                                                                  \
		rd_##K = rd_;                                                                                  \
		rs1_##K = rs1_;                                                                                \
		rs2_##K = rs2_;                                                                                \
		imm_##K = imm_;                                                                                \
		cls_packed |= (cls_K & 0x3u) << ((K) * 2);                                                     \
		op_class_or |= cls_K;                                                                          \
	} while(0)

		DECODE_SLOT(1);
		DECODE_SLOT(2);
		DECODE_SLOT(3);
		DECODE_SLOT(4);
		DECODE_SLOT(5);
		DECODE_SLOT(6);
		DECODE_SLOT(7);
#undef DECODE_SLOT
	}

	// warp-wide OR. when no lane in this warp has a MUL/DIV op, the whole warp branches past the
	// heavy paths
	U32 wc = op_class_or;
	wc |= __shfl_xor_sync(0xFFFFFFFFu, wc, 1);
	wc |= __shfl_xor_sync(0xFFFFFFFFu, wc, 2);
	wc |= __shfl_xor_sync(0xFFFFFFFFu, wc, 4);
	wc |= __shfl_xor_sync(0xFFFFFFFFu, wc, 8);
	wc |= __shfl_xor_sync(0xFFFFFFFFu, wc, 16);
	B32 warp_has_mul = (wc & 1u) != 0;
	B32 warp_has_div = (wc & 2u) != 0;

	if(cand_id >= n_candidates) return;

	U32 pass_mask = 0;
	B32 lane_alive = true;

#pragma unroll 1
	for(U32 t = 0; t < FilterTestCount; ++t) {
		B32 ok = false;
		if(lane_alive) {
			// load this test's inputs
			{
				U64* row = s_test_in + (size_t)t * active_count;
				U64 m = packed_live_in_mask;
				while(m) {
					U32 r = __ffsll((long long)m) - 1;
					m &= m - 1;
					s_regs[(size_t)r * blk_n + tid] = row[r];
				}
				s_regs[tid] = 0ull;
			}

// step macro
#define RUN_STEP(K)                                                                                \
	do {                                                                                             \
		U32 op_ = op_##K;                                                                              \
		U32 rd_ = rd_##K;                                                                              \
		U32 rs1_ = rs1_##K;                                                                            \
		U32 rs2_ = rs2_##K;                                                                            \
		U64 imm_ = imm_##K;                                                                            \
		U32 cls_ = (cls_packed >> ((K) * 2)) & 0x3u;                                                   \
		U64 a_ = s_regs[(size_t)rs1_ * blk_n + tid];                                                   \
		U64 b_ = s_regs[(size_t)rs2_ * blk_n + tid];                                                   \
		U64 v_ = sim_dispatch(op_, a_, b_, imm_, cls_, warp_has_mul, warp_has_div);                    \
		if(rd_ != 0u) { s_regs[(size_t)rd_ * blk_n + tid] = v_; }                                      \
	} while(0)

			U32 pl = PROG_LEN;
			if(pl > 0) RUN_STEP(0);
			if(pl > 1) RUN_STEP(1);
			if(pl > 2) RUN_STEP(2);
			if(pl > 3) RUN_STEP(3);
			if(pl > 4) RUN_STEP(4);
			if(pl > 5) RUN_STEP(5);
			if(pl > 6) RUN_STEP(6);
			if(pl > 7) RUN_STEP(7);
#undef RUN_STEP

			// compare against live-out targets
			ok = true;
			U64* expected_row = s_target_out + (size_t)t * active_count;
			U64 m = packed_live_mask;
			while(m) {
				U32 r = __ffsll((long long)m) - 1;
				m &= m - 1;
				if(s_regs[(size_t)r * blk_n + tid] != expected_row[r]) {
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
	pass_count[cand_id] = (pass_mask == 0xFFFFFFFFu) ? (U8)FilterTestCount : (U8)0;
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
	U64 fixed_mem_bytes = 2ull * FilterTestCount * sizeof(CpuState);
	if(usable_mem <= fixed_mem_bytes) {
		fprintf(stderr, "error: insufficient VRAM for fixed buffers\n");
		return 4;
	}
	usable_mem -= fixed_mem_bytes;

	U64 per_cand = sizeof(U8) + 2 * sizeof(U32);
	U64 chunk = usable_mem / per_cand;
	U64 hw_warps = (U64)p.multiProcessorCount * p.maxThreadsPerMultiProcessor / 32ull;
	U64 ideal_lower = hw_warps * 8ull;
	if(chunk < ideal_lower) chunk = ideal_lower;
	if(chunk < 1024) chunk = 1024;
	if(max_chunk_cands != 0 && max_chunk_cands < chunk) chunk = max_chunk_cands;
	U64 cpb = FilterCandsPerBlock;
	U64 padded_chunk = chunk + cpb - 1;
	chunk = (padded_chunk / cpb) * cpb;
	filter->max_chunk_cands = chunk;

	dmalloc(&filter->d_test_in, FilterTestCount * sizeof(CpuState));
	dmalloc(&filter->d_target_out, FilterTestCount * sizeof(CpuState));
	dmalloc(&filter->d_pass_count, filter->max_chunk_cands * sizeof(U8));

	filter->h_pass_count_cap = filter->max_chunk_cands;
	if(cudaMallocHost((void**)&filter->h_pass_count, filter->h_pass_count_cap * sizeof(U8)) !=
		 cudaSuccess) {
		filter->h_pass_count = (U8*)malloc(filter->h_pass_count_cap * sizeof(U8));
		if(!filter->h_pass_count) return 5;
	}

	U64 used_mem = fixed_mem_bytes + filter->max_chunk_cands * sizeof(U8);

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

	U32 active_count = filter_upload_slot_idx(opt->active_mask);
	if(active_count == 0 || active_count > FilterMaxActiveRegs) {
		fprintf(
			stderr,
			"error: active register set exceeds FilterMaxActiveRegs=%d (got %u)\n",
			FilterMaxActiveRegs,
			active_count
		);
		return;
	}
	U64 packed_live_mask = filter_pack_mask(opt->live_mask);
	U64 packed_live_in_mask = filter_pack_mask(opt->live_in_mask);

	if(filter->tests_dirty) {
		U64 test_size = FilterTestCount * sizeof(CpuState);
		htod_memcpy(filter->d_test_in, opt->test_in, test_size);
		htod_memcpy(filter->d_target_out, opt->target_out, test_size);
		filter->tests_dirty = false;
	}

	U64 ts_pair = 2ull * (U64)FilterTestCount * (U64)active_count * sizeof(U64);
	U64 shared_cap = (U64)48 * 1024;
	U64 rf_cap = (shared_cap > ts_pair) ? (shared_cap - ts_pair) : 0;
	U64 max_threads_by_shared = rf_cap / ((U64)active_count * sizeof(U64));
	max_threads_by_shared &= ~(U64)31; // round down to warp
	if(max_threads_by_shared < 32) max_threads_by_shared = 32;
	if(max_threads_by_shared > FilterSimThreadsPerBlock)
		max_threads_by_shared = FilterSimThreadsPerBlock;
	U32 block_threads = (U32)max_threads_by_shared;

	U64 rf = (U64)block_threads * (U64)active_count * sizeof(U64);
	U32 shmem_bytes = (U32)(ts_pair + rf);

	U64 done = 0;
	while(done < opt->n_candidates) {
		U64 this_chunk = (opt->n_candidates - done < filter->max_chunk_cands)
											 ? (opt->n_candidates - done)
											 : filter->max_chunk_cands;

		U32 n_blocks = (U32)((this_chunk + block_threads - 1) / block_threads);
		dim3 grid(n_blocks);
		dim3 block(block_threads);

#define LAUNCH(N)                                                                                  \
	opt_filter_kernel<N><<<grid, block, shmem_bytes>>>(                                              \
		opt->tuples + done,                                                                            \
		opt->parent_code,                                                                              \
		(U8*)filter->d_pass_count,                                                                     \
		this_chunk,                                                                                    \
		packed_live_mask,                                                                              \
		packed_live_in_mask,                                                                           \
		active_count,                                                                                  \
		(CpuState*)filter->d_test_in,                                                                  \
		(CpuState*)filter->d_target_out                                                                \
	)
		switch(opt->prog_len) {
			case 1: LAUNCH(1); break;
			case 2: LAUNCH(2); break;
			case 3: LAUNCH(3); break;
			case 4: LAUNCH(4); break;
			case 5: LAUNCH(5); break;
			case 6: LAUNCH(6); break;
			case 7: LAUNCH(7); break;
			case 8: LAUNCH(8); break;
			default:
				fprintf(stderr, "error: filter_run: unsupported prog_len=%u\n", opt->prog_len);
				return;
		}
#undef LAUNCH
		check_cuda(cudaGetLastError(), "filter kernel launch");
		dtoh_memcpy(filter->h_pass_count + done, filter->d_pass_count, this_chunk * sizeof(U8));
		done += this_chunk;
	}
}
