#include "cpu/instruction.cuh"
#include "util/device.h"

namespace sup {
inst_db INST_DB_HOST;
__constant__ inst_db INST_DB_DEV;

__device__ const inst_spec* find_spec_dev(opcode op) {
	return &INST_DB_DEV.row[op];
}

static void inst_db_set_row(inst_db* d, opcode op, const c8* name,
														inst_shape shape, u8 commutative, u32 ext_bit) {
	inst_spec* r = &d->row[op];
	r->name = name;
	r->operands[0] = shape_op0(shape);
	r->operands[1] = shape_op1(shape);
	r->operands[2] = shape_op2(shape);
	r->operands[3] = OPERAND_NONE;
	r->op = op;
	r->dst_slot = shape_dst_slot(shape);
	r->src_slot = shape_src_slot(shape);
	r->src2_slot = shape_src2_slot(shape);
	r->ext = ext_bit;
	r->commutative = commutative;
}

static void inst_db_build_host(inst_db* d) {
	memset(d, 0, sizeof(*d));

#define X(TAG, MN, SHAPE, COMM)                                                \
	inst_db_set_row(d, OP_##TAG, MN, SHAPE, (u8)(COMM), EXT_RV32I);
	EXT_RV32I_OPCODES(X)
#undef X
#define X(TAG, MN, SHAPE, COMM)                                                \
	inst_db_set_row(d, OP_##TAG, MN, SHAPE, (u8)(COMM), EXT_RV64I);
	EXT_RV64I_OPCODES(X)
#undef X
#define X(TAG, MN, SHAPE, COMM)                                                \
	inst_db_set_row(d, OP_##TAG, MN, SHAPE, (u8)(COMM), EXT_RV32M);
	EXT_RV32M_OPCODES(X)
#undef X
#define X(TAG, MN, SHAPE, COMM)                                                \
	inst_db_set_row(d, OP_##TAG, MN, SHAPE, (u8)(COMM), EXT_RV64M);
	EXT_RV64M_OPCODES(X)
#undef X

	// NOP
	inst_spec* nop = &d->row[OP_NOP];
	nop->name = "nop";
	nop->operands[0] = OPERAND_NONE;
	nop->operands[1] = OPERAND_NONE;
	nop->operands[2] = OPERAND_NONE;
	nop->operands[3] = OPERAND_NONE;
	nop->op = OP_NOP;
	nop->dst_slot = -1;
	nop->src_slot = -1;
	nop->src2_slot = -1;
	nop->ext = EXT_RV32I;
	nop->commutative = 0;
}

void inst_db_load(void) {
	inst_db_build_host(&INST_DB_HOST);
	check_cuda(cudaMemcpyToSymbol(INST_DB_DEV, &INST_DB_HOST, sizeof(inst_db)),
						 "inst_db_load");
}

u8 spec_get_operand_count(const inst_spec* spec) {
	u8 i = 0;
	for(; i < 4; ++i) {
		if(spec->operands[i] == OPERAND_NONE) { break; }
	}
	return i;
}

b32 op_is_commutative(opcode op) {
	return INST_DB_HOST.row[op].commutative != 0;
}

opcode find_inst_op(string name, const operand_type* ops, u8 op_cnt) {
	for(u32 i = 0; i < (u32)OP_COUNT; ++i) {
		const inst_spec* spec = &INST_DB_HOST.row[i];
		if(name != spec->name) { continue; }
		if(spec_get_operand_count(spec) != op_cnt) { continue; }
		b32 ok = true;

		for(u8 k = 0; k < op_cnt; ++k) {
			if(spec->operands[k] != ops[k]) {
				ok = false;
				break;
			}
		}

		if(ok) { return (opcode)i; }
	}

	return OP_COUNT; // sentinel: no match
}

string operand_to_string(arena& a, inst_operand op, operand_type ty) {
	switch(ty) {
		case OPERAND_REG: return reg_name((u32)op.reg);
		case OPERAND_IMM: return string::format(a, "%lld", (i64)op.i);
		default: return "?";
	}
}

void print_enabled_extensions(u32 mask) {
	bool first = true;
	for(u32 i = 0; i < EXT_COUNT; ++i) {
		if(mask & EXT_BITS[i]) {
			printf("%s%s", first ? "" : ", ", EXT_NAMES[i]);
			first = false;
		}
	}
}
} // namespace sup