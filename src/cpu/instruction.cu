#include "cpu/instruction.cuh"
#include "util/device.h"

cpu_inst_db CPU_INST_DB_HOST;
__constant__ cpu_inst_db CPU_INST_DB_DEV;

__device__ const cpu_inst_spec* cpu_find_spec_dev(cpu_opcode op) {
	return &CPU_INST_DB_DEV.row[op];
}

static void cpu_inst_db_set_row(cpu_inst_db* d, cpu_opcode op, const c8* name,
																cpu_inst_shape shape, u8 commutative,
																u32 ext_bit) {
	cpu_inst_spec* r = &d->row[op];
	r->name = name;
	r->operands[0] = cpu_shape_op0(shape);
	r->operands[1] = cpu_shape_op1(shape);
	r->operands[2] = cpu_shape_op2(shape);
	r->operands[3] = CPU_OPERAND_NONE;
	r->op = op;
	r->dst_slot = cpu_shape_dst_slot(shape);
	r->src_slot = cpu_shape_src_slot(shape);
	r->src2_slot = cpu_shape_src2_slot(shape);
	r->ext = ext_bit;
	r->commutative = commutative;
}

static void cpu_inst_db_build_host(cpu_inst_db* d) {
	memset(d, 0, sizeof(*d));

#define X(TAG, MN, SHAPE, COMM)                                                \
	cpu_inst_db_set_row(d, OP_##TAG, MN, SHAPE, (u8)(COMM), EXT_RV32I);
	EXT_RV32I_OPCODES(X)
#undef X
#define X(TAG, MN, SHAPE, COMM)                                                \
	cpu_inst_db_set_row(d, OP_##TAG, MN, SHAPE, (u8)(COMM), EXT_RV64I);
	EXT_RV64I_OPCODES(X)
#undef X
#define X(TAG, MN, SHAPE, COMM)                                                \
	cpu_inst_db_set_row(d, OP_##TAG, MN, SHAPE, (u8)(COMM), EXT_RV32M);
	EXT_RV32M_OPCODES(X)
#undef X
#define X(TAG, MN, SHAPE, COMM)                                                \
	cpu_inst_db_set_row(d, OP_##TAG, MN, SHAPE, (u8)(COMM), EXT_RV64M);
	EXT_RV64M_OPCODES(X)
#undef X

	// NOP
	cpu_inst_spec* nop = &d->row[OP_NOP];
	nop->name = "nop";
	nop->operands[0] = CPU_OPERAND_NONE;
	nop->operands[1] = CPU_OPERAND_NONE;
	nop->operands[2] = CPU_OPERAND_NONE;
	nop->operands[3] = CPU_OPERAND_NONE;
	nop->op = OP_NOP;
	nop->dst_slot = -1;
	nop->src_slot = -1;
	nop->src2_slot = -1;
	nop->ext = EXT_RV32I;
	nop->commutative = 0;
}

void cpu_inst_db_load(void) {
	cpu_inst_db_build_host(&CPU_INST_DB_HOST);
	check_cuda(
		cudaMemcpyToSymbol(CPU_INST_DB_DEV, &CPU_INST_DB_HOST, sizeof(cpu_inst_db)),
		"cpu_inst_db_load");
}

u8 cpu_spec_get_operand_count(const cpu_inst_spec* spec) {
	u8 i = 0;
	for(; i < 4; ++i) {
		if(spec->operands[i] == CPU_OPERAND_NONE) { break; }
	}
	return i;
}

b32 cpu_op_is_commutative(cpu_opcode op) {
	return CPU_INST_DB_HOST.row[op].commutative != 0;
}

cpu_opcode cpu_find_inst_op(str name, const cpu_operand_type* ops, u8 op_cnt) {
	for(u32 i = 0; i < (u32)OP_COUNT; ++i) {
		const cpu_inst_spec* spec = &CPU_INST_DB_HOST.row[i];
		if(name != spec->name) { continue; }
		if(cpu_spec_get_operand_count(spec) != op_cnt) { continue; }
		b32 ok = true;

		for(u8 k = 0; k < op_cnt; ++k) {
			if(spec->operands[k] != ops[k]) {
				ok = false;
				break;
			}
		}

		if(ok) { return (cpu_opcode)i; }
	}

	return OP_COUNT; // sentinel: no match
}

str cpu_operand_to_string(arena* a, cpu_inst_operand op, cpu_operand_type ty) {
	switch(ty) {
		case CPU_OPERAND_REG: return cpu_reg_name((u32)op.reg);
		case CPU_OPERAND_IMM: return str::format(*a, "%lld", (i64)op.i);
		default: return "?";
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
