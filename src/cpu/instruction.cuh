#ifndef CPU_INSTRUCTION_CUH
#define CPU_INSTRUCTION_CUH

#include "cpu/cpu.cuh"
#include "ext/rv32i/opcodes.def"
#include "ext/rv32m/opcodes.def"
#include "ext/rv64i/opcodes.def"
#include "ext/rv64m/opcodes.def"
#include "utl/arr.h"
#include "utl/str.h"

// to add a new extension:
// - append it to the EXTENSION_LIST macro below
// - create src/ext/<name>/ext.cuh defining the X-macro and the run handler
// - #include it below in the extensions section and append to EXT_OPCODE_LIST
// - add a Z3.cc file that exposes ext_<name>_smt(...)
// - wire those into smt/smt.cc and opt/batch_runner.cuh's dispatcher

#define EXTENSION_LIST(X)                                                                          \
	X(RV32I, "rv32i", 0)                                                                             \
	X(RV64I, "rv64i", 1)                                                                             \
	X(RV32M, "rv32m", 2)                                                                             \
	X(RV64M, "rv64m", 3)

#define EXT_OPCODE_LIST(X)                                                                         \
	EXT_RV32I_OPCODES(X)                                                                             \
	EXT_RV64I_OPCODES(X)                                                                             \
	EXT_RV32M_OPCODES(X)                                                                             \
	EXT_RV64M_OPCODES(X)

typedef enum cpu_inst_shape : u8 {
	SHAPE_NONE = 0, // nop
	SHAPE_RRR,			// rd, rs1, rs2
	SHAPE_RRI,			// rd, rs1, imm
	SHAPE_RR,				// rd, rs1
	SHAPE_RI,				// rd, imm
} cpu_inst_shape;

// EXT_RV32I is the base ISA and is always implied
// rv64-prefixed extensions extend their rv32 counterpart and require
// it to be enabled. The optimizer's pool builder enforces this implicitly
typedef enum cpu_inst_ext_bits : u32 {
#define X(TAG, DIR, BIT) EXT_##TAG = 1u << (BIT),
	EXTENSION_LIST(X)
#undef X
} cpu_inst_ext_bits;

// array of all extension directory names
inline constexpr const char* CPU_EXT_NAMES[] = {
#define X(TAG, DIR, BIT) DIR,
	EXTENSION_LIST(X)
#undef X
};

inline constexpr u32 CPU_EXT_BITS[] = {
#define X(TAG, DIR, BIT) (1u << (BIT)),
	EXTENSION_LIST(X)
#undef X
};

#define CPU_EXT_COUNT sizeof(CPU_EXT_NAMES) / sizeof(CPU_EXT_NAMES[0])

typedef enum cpu_opcode : u16 {
#define X(TAG, mnemonic, shape, comm) OP_##TAG,
	EXT_OPCODE_LIST(X)
#undef X
		OP_NOP,
	OP_COUNT,
} cpu_opcode;

typedef struct cpu_inst {
	typedef union operand {
		cpu_reg_index reg;
		u64 i;
	} operand;
	cpu_opcode op;
	operand operands[4];
} cpu_inst;

typedef struct cpu_inst_spec {
	typedef enum operand : u8 {
		NONE = 0,
		REG,
		IMM,
	} operand;

	const char* name;
	operand operands[4];
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

SO_HD constexpr cpu_inst_spec::operand cpu_shape_op0(cpu_inst_shape s) {
	return s == SHAPE_NONE ? cpu_inst_spec::NONE : cpu_inst_spec::REG;
}

SO_HD constexpr cpu_inst_spec::operand cpu_shape_op1(cpu_inst_shape s) {
	switch(s) {
		case SHAPE_RRR:
		case SHAPE_RRI:
		case SHAPE_RR: return cpu_inst_spec::REG;
		case SHAPE_RI: return cpu_inst_spec::IMM;
		default: return cpu_inst_spec::NONE;
	}
}

SO_HD constexpr cpu_inst_spec::operand cpu_shape_op2(cpu_inst_shape s) {
	switch(s) {
		case SHAPE_RRR: return cpu_inst_spec::REG;
		case SHAPE_RRI: return cpu_inst_spec::IMM;
		default: return cpu_inst_spec::NONE;
	}
}

SO_HD constexpr i8 cpu_shape_dst_slot(cpu_inst_shape s) { return s == SHAPE_NONE ? (i8)-1 : (i8)0; }

SO_HD constexpr i8 cpu_shape_src_slot(cpu_inst_shape s) {
	switch(s) {
		case SHAPE_RRR:
		case SHAPE_RRI:
		case SHAPE_RR: return 1;
		default: return -1;
	}
}

SO_HD constexpr i8 cpu_shape_src2_slot(cpu_inst_shape s) { return s == SHAPE_RRR ? (i8)2 : (i8)-1; }

SO_HD constexpr cpu_inst_db cpu_build_inst_db() {
	cpu_inst_db d = {};

#define ROW(TAG, MN, SHAPE, COMM, EXT_BIT)                                                         \
	d.row[OP_##TAG] = cpu_inst_spec{                                                                 \
		MN,                                                                                            \
		{cpu_shape_op0(SHAPE), cpu_shape_op1(SHAPE), cpu_shape_op2(SHAPE), cpu_inst_spec::NONE},       \
		OP_##TAG,                                                                                      \
		cpu_shape_dst_slot(SHAPE),                                                                     \
		cpu_shape_src_slot(SHAPE),                                                                     \
		cpu_shape_src2_slot(SHAPE),                                                                    \
		(u32)(EXT_BIT),                                                                                \
		(u8)(COMM)};

#define X(TAG, MN, SHAPE, COMM) ROW(TAG, MN, SHAPE, COMM, EXT_RV32I)
	EXT_RV32I_OPCODES(X)
#undef X
#define X(TAG, MN, SHAPE, COMM) ROW(TAG, MN, SHAPE, COMM, EXT_RV64I)
	EXT_RV64I_OPCODES(X)
#undef X
#define X(TAG, MN, SHAPE, COMM) ROW(TAG, MN, SHAPE, COMM, EXT_RV32M)
	EXT_RV32M_OPCODES(X)
#undef X
#define X(TAG, MN, SHAPE, COMM) ROW(TAG, MN, SHAPE, COMM, EXT_RV64M)
	EXT_RV64M_OPCODES(X)
#undef X

#undef ROW
	d.row[OP_NOP] = cpu_inst_spec{
		"nop",		 {cpu_inst_spec::NONE, cpu_inst_spec::NONE, cpu_inst_spec::NONE, cpu_inst_spec::NONE},
		OP_NOP,		 -1,
		-1,				 -1,
		EXT_RV32I, 0};
	return d;
}

inline constexpr cpu_inst_db CPU_INST_DB_HOST = cpu_build_inst_db();

#ifdef __CUDACC__
static __constant__ cpu_inst_db CPU_INST_DB_DEV = cpu_build_inst_db();
#endif // #ifdef __CUDACC__

SO_HD const cpu_inst_spec* cpu_find_spec(cpu_opcode op) {
#ifdef __CUDA_ARCH__
	return &CPU_INST_DB_DEV.row[op];
#else
	return &CPU_INST_DB_HOST.row[op];
#endif // #ifdef __CUDA_ARCH__
}

ARR_DECL(cpu_inst, cpu_inst_arr)

u8 cpu_spec_get_operand_count(const cpu_inst_spec* spec);
b32 cpu_op_is_commutative(cpu_opcode op);
cpu_opcode cpu_find_inst_op(str name, const cpu_inst_spec::operand* operands, u8 op_count);
str cpu_operand_to_string(arena* a, cpu_inst::operand op, cpu_inst_spec::operand ty);
void cpu_print_enabled_extensions(u32 mask);

#endif // #ifndef CPU_INSTRUCTION_CUH
