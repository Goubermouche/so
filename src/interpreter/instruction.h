#ifndef INSTRUCTION_H
#define INSTRUCTION_H

#include "interpreter/cpu_state.h"

namespace so {
	enum opcode {
		OP_MOV_R64_R64,
		OP_MOV_R64_I64,
		OP_ADD_R64_R64,
		OP_ADD_R64_I64,
		OP_NEG_R64,
		OP_AND_R64_R64,
		OP_XOR_R64_R64,
		OP_NOT_R64,
	};

	// executable instruction
	struct inst {
		using operand = union {
			reg_index reg;
			u64 i;
		};

		opcode op;
		operand operands[4];
	};

	// instruction specification
	struct inst_spec {
		enum operand {
			NONE = 0,
			R64,
			I64,
		};

		inline u8 get_operand_count() const {
			u8 i = 0;
			for(; i < 4; ++i) {
				if(operands[i] == NONE) {
					break;
				}
			}

			return i;
		}

		const char* name;
		operand operands[4];
		opcode op;
	};

	static inst_spec INST_DB[] = {
		{ "mov", { inst_spec::R64, inst_spec::R64, inst_spec::NONE, inst_spec::NONE }, OP_MOV_R64_R64 },
		{ "mov", { inst_spec::R64, inst_spec::I64, inst_spec::NONE, inst_spec::NONE }, OP_MOV_R64_I64 },
		{ "add", { inst_spec::R64, inst_spec::R64, inst_spec::NONE, inst_spec::NONE }, OP_ADD_R64_R64 },
		{ "add", { inst_spec::R64, inst_spec::I64, inst_spec::NONE, inst_spec::NONE }, OP_ADD_R64_I64 },
		{ "neg", { inst_spec::R64, inst_spec::NONE, inst_spec::NONE, inst_spec::NONE }, OP_NEG_R64 },
		{ "and", { inst_spec::R64, inst_spec::R64, inst_spec::NONE, inst_spec::NONE }, OP_AND_R64_R64 },
		{ "xor", { inst_spec::R64, inst_spec::R64, inst_spec::NONE, inst_spec::NONE }, OP_XOR_R64_R64 },
		{ "not", { inst_spec::R64, inst_spec::NONE, inst_spec::NONE, inst_spec::NONE }, OP_NOT_R64 }
	};

	static u64 INST_DB_SIZE = sizeof(INST_DB) / sizeof(INST_DB[0]);

	inline opcode find_inst_op(const str& name, const inst_spec::operand* operands, u8 operand_count) {
		for(u64 i = 0; i < INST_DB_SIZE; ++i) {
			const inst_spec& inst = INST_DB[i];

			if(strcmp(name.c_str(), inst.name) != 0) {
				continue;
			}

			if(memcmp(operands, inst.operands, sizeof(inst.operands)) != 0) {
				continue;
			}

			return inst.op;
		}

		ASSERT(false, "find_inst_op: unknown instruction {}\n", name);
		return static_cast<opcode>(0);
	}

	inline const inst_spec& find_spec(opcode op) {
		for(u64 i = 0; i < INST_DB_SIZE; ++i) {
			const inst_spec& inst = INST_DB[i];

			if(inst.op == op) {
				return inst;
			}
		}

		ASSERT(false, "find_spec: unknown opcode\n");
		return INST_DB[0];
	}
}

#endif // INSTRUCTION_H

