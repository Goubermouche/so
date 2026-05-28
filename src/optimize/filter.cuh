#ifndef OPT_DRIVER_CUH
#define OPT_DRIVER_CUH

#include "cpu/program.h"
#include "extensions/rv32i/run.cuh"
#include "extensions/rv32m/run.cuh"
#include "extensions/rv64i/run.cuh"
#include "extensions/rv64m/run.cuh"
#include "optimize/enumerate.cuh"

#define FilterTestCount 32
#define FilterWarpsPerBlock 8

// maximum packed active-register count. The host computes the active mask per launch and packs raw
// RISC-V indices (0..31) into a dense [0..K) range
#define FilterMaxActiveRegs 24

#define FilterCandsPerWarp 32
#define FilterSimWarpsPerBlock 8
#define FilterCandsPerBlock (FilterSimWarpsPerBlock * FilterCandsPerWarp)
#define FilterSimThreadsPerBlock (FilterSimWarpsPerBlock * 32)

typedef struct Filter {
	U64 max_chunk_cands;
	// device
	void* d_test_in;		// reference inputs
	void* d_target_out; // reference outputs
	void* d_pass_count; // per-candidate pass counts
	// host
	U8* h_pass_count;
	U64 h_pass_count_cap;
	B32 tests_dirty;
} Filter;

typedef struct FilterOptions {
	U64 live_mask;
	U64 live_in_mask;
	U64 active_mask;
	U32 prog_len;
	U64* tuples;                // per-cand U64 (parent_local_id, op, rd, rs1, rs2/imm, is_imm)
	EnumStateCode* parent_code; // indexed by parent_local_id
	U64 n_candidates;
	CpuState* test_in;
	CpuState* target_out;
} FilterOptions;

I32 filter_make(Filter* filter, U64 max_chunk_cands);
void filter_free(Filter* filter);
void filter_mark_tests_dirty(Filter* filter);
void filter_run(Filter* filter, FilterOptions* opt, U8** out_pass_counts);

U32 filter_upload_slot_idx(U64 active_mask);
U64 filter_pack_mask(U64 raw_mask);
void filter_init_decode_info();
void filter_upload_meta(EnumMeta* h_meta, U32 n_meta, I64* h_imms, U32 n_imms);

HostDevice void filter_run_lane(U64 regs[32], Instruction* prog, U32 prog_len) {
	regs[0] = 0;

	for(U32 i = 0; i < prog_len; ++i) {
		Instruction* in = &prog[i];
		U32 op = (U32)in->op;

		if(op == InstructionOpcode_Nop) { continue; }

		if(ext_rv32i_run(op, regs, in)) { continue; };
		if(ext_rv64i_run(op, regs, in)) { continue; };
		if(ext_rv32m_run(op, regs, in)) { continue; };
		if(ext_rv64m_run(op, regs, in)) { continue; };
	}
}

inline CpuState filter_run_host(Program* prog, CpuState* in) {
	CpuState out = *in;
	out.regs[0] = 0;
	filter_run_lane(out.regs, prog->instructions, prog->size);
	return out;
}

#endif // #ifndef OPT_DRIVER_CUH
