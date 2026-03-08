#ifndef EMULATOR_CUH
#define EMULATOR_CUH

#include "instruction.cuh"

namespace so {
	struct cpu_state {
		u32 regs[REG_COUNT];
	};

	// generate handler functions
#define X(id, name, op1, op2, op3, op4, body) \
	HD __forceinline__ void exec_##id(cpu_state& state, const inst& ins) { \
		u32& dst = state.regs[ins.ops[0].r]; \
		body \
	}
	INST_LIST
#undef X

	HD __forceinline__ void execute_inst(cpu_state& state, const inst& ins) {
		u32& dst = state.regs[ins.ops[0].r];
		switch(ins.id) {
#define X(id, name, op1, op2, op3, op4, body) case id: body break;
			INST_LIST
#undef X
			default: break;
		}
	}

	__device__ void run_program(const inst* prog, u32 prog_len, cpu_state& state) {
		for(u32 i = 0; i < prog_len; ++i) {
			execute_inst(state, prog[i]);
		}
	}
} // namespace so

#endif // #ifndef EMULATOR_CUH
