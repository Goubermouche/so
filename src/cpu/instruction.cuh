#ifndef INSTRUCTION_CUH
#define INSTRUCTION_CUH

#include "cpu/cpu.cuh"
#include "extensions/rv32i/opcodes.def"
#include "extensions/rv32m/opcodes.def"
#include "extensions/rv64i/opcodes.def"
#include "extensions/rv64m/opcodes.def"
#include "util/array.h"
#include "util/string.h"

namespace sup {
#define MaxProgramLen 8

#define EXTENSION_LIST(X)                                                      \
	X(RV32I, "rv32i", 0)                                                         \
	X(RV64I, "rv64i", 1)                                                         \
	X(RV32M, "rv32m", 2)                                                         \
	X(RV64M, "rv64m", 3)

#define EXT_OPCODE_LIST(X)                                                     \
	EXT_RV32I_OPCODES(X)                                                         \
	EXT_RV64I_OPCODES(X)                                                         \
	EXT_RV32M_OPCODES(X)                                                         \
	EXT_RV64M_OPCODES(X)

enum inst_shape {
	SHAPE_NONE = 0, // nop
	SHAPE_RRR,			// rd, rs1, rs2
	SHAPE_RRI,			// rd, rs1, imm
	SHAPE_RR,				// rd, rs1
	SHAPE_RI,				// rd, imm
};

// EXT_RV32I is the base ISA and is always implied
// rv64-prefixed extensions extend their rv32 counterpart and require
// it to be enabled. The optimizer's pool builder enforces this implicitly
enum inst_ext_bits {
#define X(TAG, DIR, BIT) EXT_##TAG = 1u << (BIT),
	EXTENSION_LIST(X)
#undef X
};

// array of all extension directory names
static const c8* const EXT_NAMES[] = {
#define X(TAG, DIR, BIT) DIR,
	EXTENSION_LIST(X)
#undef X
};

static const u32 EXT_BITS[] = {
#define X(TAG, DIR, BIT) (1u << (BIT)),
	EXTENSION_LIST(X)
#undef X
};

static constexpr u64 EXT_COUNT = (sizeof(EXT_NAMES) / sizeof(EXT_NAMES[0]));

enum opcode {
#define X(TAG, mnemonic, shape, comm) OP_##TAG,
	EXT_OPCODE_LIST(X)
#undef X
		OP_NOP,
	OpCount,
};

union inst_operand {
	reg_index reg;
	u64 i;
};

struct inst {
	opcode op;
	inst_operand operands[4];
};

enum operand_type {
	OPERAND_NONE = 0,
	OPERAND_REG,
	OPERAND_IMM,
};

struct inst_spec {
	const c8* name;
	operand_type operands[4];
	opcode op;
	i8 dst_slot;
	i8 src_slot;
	i8 src2_slot;
	u32 ext;
	u8 commutative;
};

struct inst_db {
	inst_spec row[OpCount];
};

static inline operand_type shape_op0(inst_shape s) {
	return s == SHAPE_NONE ? OPERAND_NONE : OPERAND_REG;
}

static inline operand_type shape_op1(inst_shape s) {
	switch(s) {
		case SHAPE_RRR:
		case SHAPE_RRI:
		case SHAPE_RR: return OPERAND_REG;
		case SHAPE_RI: return OPERAND_IMM;
		default: return OPERAND_NONE;
	}
}

static inline operand_type shape_op2(inst_shape s) {
	switch(s) {
		case SHAPE_RRR: return OPERAND_REG;
		case SHAPE_RRI: return OPERAND_IMM;
		default: return OPERAND_NONE;
	}
}

static inline i8 shape_dst_slot(inst_shape s) {
	return s == SHAPE_NONE ? (i8)-1 : (i8)0;
}

static inline i8 shape_src_slot(inst_shape s) {
	switch(s) {
		case SHAPE_RRR:
		case SHAPE_RRI:
		case SHAPE_RR: return 1;
		default: return -1;
	}
}

static inline i8 shape_src2_slot(inst_shape s) {
	return s == SHAPE_RRR ? (i8)2 : (i8)-1;
}

extern inst_db INST_DB_HOST;

void inst_db_load(void);

#ifdef __CUDACC__
__device__ const inst_spec* find_spec_dev(opcode op);
#endif // #ifdef __CUDACC__

SO_HD const inst_spec* find_spec(opcode op) {
#ifdef __CUDA_ARCH__
	return find_spec_dev(op);
#else
	return &INST_DB_HOST.row[op];
#endif // #ifdef __CUDA_ARCH__
}

u8 spec_get_operand_count(const inst_spec* spec);
b32 op_is_commutative(opcode op);
opcode find_inst_op(string name, const operand_type* ops, u8 op_cnt);
string operand_to_string(arena& a, inst_operand op, operand_type ty);
void print_enabled_extensions(u32 mask);

} // namespace sup

#endif // #ifndef INSTRUCTION_CUH
