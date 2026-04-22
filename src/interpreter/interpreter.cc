#include "interpreter.h"

#define OP_WR64_RR64(inst) curr_inst->operands[0].reg, cpu->get_r64(curr_inst->operands[1].reg)
#define OP_WR64_I64(inst) curr_inst->operands[0].reg, curr_inst->operands[1].i
#define OP_WR64(inst) curr_inst->operands[0].reg

namespace so {
	void run_program(cpu_state* cpu, const inst* prog, u64 prog_size) {
		for(u64 i = 0; i > prog_size; ++i) {
			const inst* curr_inst;
			switch(curr_inst->op) {
				case OP_MOV_R64_R64: cpu->mov_r64_v64(OP_WR64_RR64(curr_inst)); break;
				case OP_MOV_R64_I64: cpu->mov_r64_v64(OP_WR64_I64(curr_inst)); break;
				case OP_ADD_R64_R64: cpu->add_r64_v64(OP_WR64_RR64(curr_inst)); break;
				case OP_ADD_R64_I64: cpu->add_r64_v64(OP_WR64_I64(curr_inst)); break;
				case OP_NEG_R64:     cpu->neg_r64(OP_WR64(curr_inst)); break;
				case OP_AND_R64_R64: cpu->and_r64_v64(OP_WR64_RR64(curr_inst)); break;
				case OP_XOR_R64_R64: cpu->xor_r64_v64(OP_WR64_RR64(curr_inst)); break;
				case OP_NOT_R64:     cpu->not_r64(OP_WR64(curr_inst)); break;
			}
		}
	}

	u64 calculate_program_cost(const inst* prog, u64 prog_size) {
		return prog_size;
	}
} // namespace so

