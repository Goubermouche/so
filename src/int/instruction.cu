#include "int/instruction.cuh"

u8 int_spec_get_operand_count(const int_inst_spec* spec) {
	u8 i = 0;
	for(; i < 4; ++i) {
		if(spec->operands[i] == int_inst_spec::NONE) { break; }
	}
	return i;
}

b32 int_op_is_commutative(int_opcode op) {
	return INT_INST_DB_HOST.row[op].commutative != 0;
}

int_opcode int_find_inst_op(const str& name, const int_inst_spec::operand* operands, u8 op_count) {
	for(u32 i = 0; i < (u32)OP_COUNT; ++i) {
		const int_inst_spec* spec = &INT_INST_DB_HOST.row[i];
		if(name != spec->name) { continue; }
		if(int_spec_get_operand_count(spec) != op_count) { continue; }
		b32 ok = true;

		for(u8 k = 0; k < op_count; ++k) {
			if(spec->operands[k] != operands[k]) {
				ok = false;
				break;
			}
		}

		if(ok) { return (int_opcode)i; }
	}

	return OP_COUNT; // sentinel: no match
}

str int_operand_to_string(int_inst::operand op, int_inst_spec::operand ty) {
	switch(ty) {
		case int_inst_spec::REG: return int_reg_name((u32)op.reg);
		case int_inst_spec::IMM: return std::to_string((i64)op.i);
		default: return "?";
	}
}


void int_print_enabled_extensions(u32 mask) {
	bool first = true;
	for(u32 i = 0; i < INT_EXT_COUNT; ++i) {
		if(mask & INT_EXT_BITS[i]) {
			std::printf("%s%s", first ? "" : ", ", INT_EXT_NAMES[i]);
			first = false;
		}
	}
}
