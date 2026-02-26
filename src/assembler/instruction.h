#ifndef INSTRUCTION_H
#define INSTRUCTION_H

#include "utility/type.h"

namespace so {
	enum opcode {
		OP_NONE,
		OP_MOV,
		OP_SUB,
		OP_NOT,
		OP_AND,
		OP_NEG
	};

	auto opcode_to_string(opcode op) -> const char*;

	struct operand {
		enum type {
			OPERAND_NONE,
			OPERAND_REG,
			OPERAND_IMM
		};

		auto to_string() const -> str;

		static auto make_reg(u64 index) -> operand;
		static auto make_imm(u64 value) -> operand;
	private:
		type m_type = OPERAND_NONE;
		u64 m_value;
	};

	struct inst {
		auto to_string() const -> str;

		opcode op;
		operand operands[2];
		u8 operand_count;
	};
} // namespace so

#endif // #ifndef INSTRUCTION_H
