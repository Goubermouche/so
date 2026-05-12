#include "cpu/instruction.cuh"

u8 cpu_spec_get_operand_count(const cpu_inst_spec* spec) {
	u8 i = 0;
	for(; i < 4; ++i) {
		if(spec->operands[i] == cpu_inst_spec::NONE) { break; }
	}
	return i;
}

b32 cpu_op_is_commutative(cpu_opcode op) {
	return CPU_INST_DB_HOST.row[op].commutative != 0;
}

cpu_opcode cpu_find_inst_op(str name, const cpu_inst_spec::operand* operands, u8 op_count) {
	for(u32 i = 0; i < (u32)OP_COUNT; ++i) {
		const cpu_inst_spec* spec = &CPU_INST_DB_HOST.row[i];
		if(!str_eq_cstr(name, spec->name)) { continue; }
		if(cpu_spec_get_operand_count(spec) != op_count) { continue; }
		b32 ok = true;

		for(u8 k = 0; k < op_count; ++k) {
			if(spec->operands[k] != operands[k]) {
				ok = false;
				break;
			}
		}

		if(ok) { return (cpu_opcode)i; }
	}

	return OP_COUNT; // sentinel: no match
}

str cpu_operand_to_string(arena* a, cpu_inst::operand op, cpu_inst_spec::operand ty) {
	switch(ty) {
		case cpu_inst_spec::REG: return str_cstring(cpu_reg_name((u32)op.reg));
		case cpu_inst_spec::IMM: return str_push_fmt(a, "%lld", (i64)op.i);
		default: return STR_LIT("?");
	}
}

void cpu_print_enabled_extensions(u32 mask) {
	bool first = true;
	for(u32 i = 0; i < CPU_EXT_COUNT; ++i) {
		if(mask & CPU_EXT_BITS[i]) {
			printf("%s%s", first ? "" : ", ", CPU_EXT_NAMES[i]);
			first = false;
		}
	}
}
