#ifndef CPU_INSTRUCTION_CUH
#define CPU_INSTRUCTION_CUH

#include "cpu/cpu.cuh"
#include "extensions/rv32i/opcodes.def"
#include "extensions/rv32m/opcodes.def"
#include "extensions/rv64i/opcodes.def"
#include "extensions/rv64m/opcodes.def"
#include "util/array.h"
#include "util/str.h"

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

typedef enum cpu_inst_shape {
	SHAPE_NONE = 0, // nop
	SHAPE_RRR,			// rd, rs1, rs2
	SHAPE_RRI,			// rd, rs1, imm
	SHAPE_RR,				// rd, rs1
	SHAPE_RI,				// rd, imm
} cpu_inst_shape;

// EXT_RV32I is the base ISA and is always implied
// rv64-prefixed extensions extend their rv32 counterpart and require
// it to be enabled. The optimizer's pool builder enforces this implicitly
typedef enum cpu_inst_ext_bits {
#define X(TAG, DIR, BIT) EXT_##TAG = 1u << (BIT),
	EXTENSION_LIST(X)
#undef X
} cpu_inst_ext_bits;

// array of all extension directory names
static const c8* const CPU_EXT_NAMES[] = {
#define X(TAG, DIR, BIT) DIR,
	EXTENSION_LIST(X)
#undef X
};

static const u32 CPU_EXT_BITS[] = {
#define X(TAG, DIR, BIT) (1u << (BIT)),
	EXTENSION_LIST(X)
#undef X
};

#define CPU_EXT_COUNT (sizeof(CPU_EXT_NAMES) / sizeof(CPU_EXT_NAMES[0]))

typedef enum cpu_opcode {
#define X(TAG, mnemonic, shape, comm) OP_##TAG,
	EXT_OPCODE_LIST(X)
#undef X
		OP_NOP,
	OP_COUNT,
} cpu_opcode;

typedef union cpu_inst_operand {
	cpu_reg_index reg;
	u64 i;
} cpu_inst_operand;

typedef struct cpu_inst {
	cpu_opcode op;
	cpu_inst_operand operands[4];
} cpu_inst;

typedef enum cpu_operand_type {
	CPU_OPERAND_NONE = 0,
	CPU_OPERAND_REG,
	CPU_OPERAND_IMM,
} cpu_operand_type;

typedef struct cpu_inst_spec {
	const c8* name;
	cpu_operand_type operands[4];
	cpu_opcode op;
	i8 dst_slot;
	i8 src_slot;
	i8 src2_slot;
	u32 ext;
	u8 commutative;
} cpu_inst_spec;

typedef struct cpu_inst_db {
	cpu_inst_spec row[OP_COUNT];
} cpu_inst_db;

static inline cpu_operand_type cpu_shape_op0(cpu_inst_shape s) {
	return s == SHAPE_NONE ? CPU_OPERAND_NONE : CPU_OPERAND_REG;
}

static inline cpu_operand_type cpu_shape_op1(cpu_inst_shape s) {
	switch(s) {
		case SHAPE_RRR:
		case SHAPE_RRI:
		case SHAPE_RR: return CPU_OPERAND_REG;
		case SHAPE_RI: return CPU_OPERAND_IMM;
		default: return CPU_OPERAND_NONE;
	}
}

static inline cpu_operand_type cpu_shape_op2(cpu_inst_shape s) {
	switch(s) {
		case SHAPE_RRR: return CPU_OPERAND_REG;
		case SHAPE_RRI: return CPU_OPERAND_IMM;
		default: return CPU_OPERAND_NONE;
	}
}

static inline i8 cpu_shape_dst_slot(cpu_inst_shape s) {
	return s == SHAPE_NONE ? (i8)-1 : (i8)0;
}

static inline i8 cpu_shape_src_slot(cpu_inst_shape s) {
	switch(s) {
		case SHAPE_RRR:
		case SHAPE_RRI:
		case SHAPE_RR: return 1;
		default: return -1;
	}
}

static inline i8 cpu_shape_src2_slot(cpu_inst_shape s) {
	return s == SHAPE_RRR ? (i8)2 : (i8)-1;
}

extern cpu_inst_db CPU_INST_DB_HOST;

void cpu_inst_db_load(void);

#ifdef __CUDACC__
__device__ const cpu_inst_spec* cpu_find_spec_dev(cpu_opcode op);
#endif // #ifdef __CUDACC__

SO_HD const cpu_inst_spec* cpu_find_spec(cpu_opcode op) {
#ifdef __CUDA_ARCH__
	return cpu_find_spec_dev(op);
#else
	return &CPU_INST_DB_HOST.row[op];
#endif // #ifdef __CUDA_ARCH__
}

u8 cpu_spec_get_operand_count(const cpu_inst_spec* spec);
b32 cpu_op_is_commutative(cpu_opcode op);
cpu_opcode cpu_find_inst_op(str name, const cpu_operand_type* ops, u8 op_cnt);
str cpu_operand_to_string(arena* a, cpu_inst_operand op, cpu_operand_type ty);
void cpu_print_enabled_extensions(u32 mask);

#endif // #ifndef CPU_INSTRUCTION_CUH
