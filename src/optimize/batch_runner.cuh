#ifndef OPT_BATCH_RUNNER_CUH
#define OPT_BATCH_RUNNER_CUH

#include "cpu/program.h"
#include "extensions/rv32i/run.cuh"
#include "extensions/rv32m/run.cuh"
#include "extensions/rv64i/run.cuh"
#include "extensions/rv64m/run.cuh"

namespace sup {
SO_HD void opt_lane_run(u64 regs[32], const inst* prog, u32 prog_len) {
	regs[0] = 0;

	for(u32 i = 0; i < prog_len; ++i) {
		const inst* in = &prog[i];
		const u32 op = (u32)in->op;

		if(op == OP_NOP) { continue; }

		if(ext_rv32i_run(op, regs, in)) { continue; };
		if(ext_rv64i_run(op, regs, in)) { continue; };
		if(ext_rv32m_run(op, regs, in)) { continue; };
		if(ext_rv64m_run(op, regs, in)) { continue; };
	}
}

inline cpu_state opt_host_run(const program& prog, const cpu_state* in) {
	cpu_state out = *in;
	out.regs[0] = 0;
	opt_lane_run(out.regs, prog.ptr, prog.size);
	return out;
}
} // namespace sup

#endif // #ifndef OPT_BATCH_RUNNER_CUH
