#ifndef BATCH_RUNNER_CUH
#define BATCH_RUNNER_CUH

#include "ext/rv32i/run.cuh"
#include "ext/rv32m/run.cuh"
#include "ext/rv64i/run.cuh"
#include "ext/rv64m/run.cuh"
#include "int/program.h"

SO_HD void opt_lane_run(u64 regs[32], const int_inst* prog, u32 prog_len) {
	regs[0] = 0;

	for(u32 i = 0; i < prog_len; ++i) {
		const int_inst* in = &prog[i];
		const u32 op = (u32)in->op;

		if(op == OP_NOP) { continue; }

		if(ext_rv32i_run(op, regs, in)) { continue; };
		if(ext_rv64i_run(op, regs, in)) { continue; };
		if(ext_rv32m_run(op, regs, in)) { continue; };
		if(ext_rv64m_run(op, regs, in)) { continue; };
	}
}

inline int_cpu_state opt_host_run(const int_program* prog, const int_cpu_state* in) {
	int_cpu_state out = *in;
	out.regs[0] = 0;
	opt_lane_run(out.regs, prog->instructions, prog->size);
	return out;
}

#endif // #ifndef BATCH_RUNNER_CUH
