#include "instruction.h"

namespace so {
	auto opcode_to_string(opcode op) -> const char* {
		switch(op) {
			case OP_NONE: return "none";
			case OP_MOV:  return "mov";
			case OP_SUB:  return "sub";
			case OP_NOT:  return "not";
			case OP_AND:  return "and";
			case OP_NEG:  return "neg";
			default:      return "?";
		}
	}

	auto operand::to_string() const -> str {
		switch(m_type) {
			case OPERAND_NONE: return "none";
			case OPERAND_REG: {
				static const char* regs[] = { "eax", "ebx" };
				return regs[m_value];
			}
			case OPERAND_IMM: {
				return std::to_string(m_value);
			}
			default: return "?";
		}
	}

	auto operand::make_reg(u64 index) -> operand {
		operand op;
		op.m_type = OPERAND_REG;
		op.m_value = index;
		return op;
	}

	auto operand::make_imm(u64 value) -> operand {
		operand op;
		op.m_type = OPERAND_IMM;
		op.m_value = value;
		return op;
	}

	auto inst::to_string() const -> str {
		str out = opcode_to_string(op);
		out += "   ";

		for(i8 i = 0; i < operand_count - 1; ++i) {
			out += operands[i].to_string();
			out += ", ";
		}
		out += operands[operand_count - 1].to_string();
		return out;
	}
} // namespace so

