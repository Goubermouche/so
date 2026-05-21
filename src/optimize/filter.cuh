#ifndef OPT_DRIVER_CUH
#define OPT_DRIVER_CUH

#include "cpu/program.h"
#include "extensions/rv32i/run.cuh"
#include "extensions/rv32m/run.cuh"
#include "extensions/rv64i/run.cuh"
#include "extensions/rv64m/run.cuh"

#define FilterTestCount 32
#define FilterWarpsPerBlock 4
#define FilterThreadsPerBlock FilterWarpsPerBlock * 32

typedef struct Filter {
	u64 max_chunk_cands;
	// device
	void* d_cands;
	void* d_test_in;		// reference inputs
	void* d_target_out; // reference outputs
	void* d_pass_count; // per-candidate pass counts
} Filter;

typedef struct FilterOptions {
	u64 live_mask;
	u32 prog_len;
	const Instruction* candidates;
	u64 n_candidates;
	const CpuState* test_in;		 // reference inputs
	const CpuState* target_out; // reference outputs
} FilterOptions;

typedef struct FilterSharedBlock {
	Instruction progs[FilterWarpsPerBlock][MaxProgramLen];
} FilterSharedBlock;

i32  filter_make(Filter* filter, u64 max_chunk_cands);
void filter_free(Filter* filter);
void filter_run(Filter* filter, FilterOptions* opt, u8* pass_counts);

SO_HD void filter_run_lane(u64 regs[32], const Instruction* prog, u32 prog_len) {
	regs[0] = 0;

	for(u32 i = 0; i < prog_len; ++i) {
		const Instruction* in = &prog[i];
		const u32 op = (u32)in->op;

		if(op == InstructionOpcode_Nop) { continue; }

		if(ext_rv32i_run(op, regs, in)) { continue; };
		if(ext_rv64i_run(op, regs, in)) { continue; };
		if(ext_rv32m_run(op, regs, in)) { continue; };
		if(ext_rv64m_run(op, regs, in)) { continue; };
	}
}

inline CpuState filter_run_host(const Program* prog, const CpuState* in) {
	CpuState out = *in;
	out.regs[0] = 0;
	filter_run_lane(out.regs, prog->instructions, prog->size);
	return out;
}

#endif // #ifndef OPT_DRIVER_CUH
