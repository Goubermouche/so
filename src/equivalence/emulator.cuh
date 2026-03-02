#ifndef EMULATOR_CUH
#define EMULATOR_CUH

#include "instruction.cuh"

namespace so {
	struct cpu_state {
		u32 regs[REG_COUNT];
	};

	__host__ __device__ __forceinline__ void execute_inst(cpu_state& state, const inst& inst) {
		u32& dst = state.regs[inst.ops[0].r];
		switch(inst.tag) {
			case INST_MOV_RR: dst = state.regs[inst.ops[1].r];       break;
			case INST_SUB_RI: dst = dst - inst.ops[1].i;             break;
			case INST_SUB_RR: dst = dst - state.regs[inst.ops[1].r]; break;
			case INST_NOT_R:  dst = ~dst;                            break;
			case INST_AND_RR: dst = dst & state.regs[inst.ops[1].r]; break;
			case INST_NEG_R:  dst = (u32)(-(i32)dst);                break;
			case INST_OR_RR:  dst = dst | state.regs[inst.ops[1].r]; break;
			case INST_XOR_RR: dst = dst ^ state.regs[inst.ops[1].r]; break;
			case INST_SHL_RI: dst = dst << (inst.ops[1].i & 31);     break;
			case INST_SHR_RI: dst = dst >> (inst.ops[1].i & 31);     break;
			default:                                                 break;
		}
	}

	__device__ void run_program(const inst* prog, u32 prog_len, cpu_state& state) {
		for(u32 i = 0; i < prog_len; ++i) {
			execute_inst(state, prog[i]);
		}
	}
} // namespace so

#endif // #ifndef EMULATOR_CUH
