#ifndef BATCH_RUNNER_CUH
#define BATCH_RUNNER_CUH

#include "int/instruction.cuh"
#include "ext/rv32i/run.cuh"
#include "ext/rv64i/run.cuh"
#include "ext/rv32m/run.cuh"
#include "ext/rv64m/run.cuh"

namespace sup {
	SO_HD void run_program_lane(u64 regs[32], const inst* prog, u32 prog_len) {
		regs[0] = 0;

		for(u32 i = 0; i < prog_len; ++i) {
			const inst& in = prog[i];
			const u32 op = (u32)in.op;

			if(op == OP_NOP) {
				continue;
			}

			if(ext_rv32i_run(op, regs, in)) { continue; };
			if(ext_rv64i_run(op, regs, in)) { continue; };
			if(ext_rv32m_run(op, regs, in)) { continue; };
			if(ext_rv64m_run(op, regs, in)) { continue; };
		}
	}
} // namespace sup

#endif // #ifndef BATCH_RUNNER_CUH

