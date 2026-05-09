#ifndef INSTRUCTION_CUH
#define INSTRUCTION_CUH

#include "int/cpu.cuh"

// to add a new extension:
// - append it to the EXTENSION_LIST macro below
// - create src/ext/<name>/ext.cuh defining the X-macro and the run handler
// - #include it below in the extensions section and append to EXT_OPCODE_LIST
// - add a Z3.cc file that exposes ext_<name>_smt(...)
// - wire those into smt/smt.cc and opt/batch_runner.cuh's dispatcher

typedef enum int_inst_shape : u8 {
	SHAPE_NONE = 0, // nop
	SHAPE_RRR,			// rd, rs1, rs2
	SHAPE_RRI,			// rd, rs1, imm
	SHAPE_RR,				// rd, rs1
	SHAPE_RI,				// rd, imm
} int_inst_shape;

#define EXTENSION_LIST(X)                                                                          \
	X(RV32I, "rv32i", 0)                                                                             \
	X(RV64I, "rv64i", 1)                                                                             \
	X(RV32M, "rv32m", 2)                                                                             \
	X(RV64M, "rv64m", 3)

// EXT_RV32I is the base ISA and is always implied
// rv64-prefixed extensions extend their rv32 counterpart and require
// it to be enabled. The optimizer's pool builder enforces this implicitly
typedef enum inst_ext_bits : u32 {
#define X(TAG, DIR, BIT) EXT_##TAG = 1u << (BIT),
	EXTENSION_LIST(X)
#undef X
} inst_ext_bits;

// array of all extension directory names
inline constexpr const char* INT_EXT_NAMES[] = {
#define X(TAG, DIR, BIT) DIR,
	EXTENSION_LIST(X)
#undef X
};

inline constexpr u32 INT_EXT_BITS[] = {
#define X(TAG, DIR, BIT) (1u << (BIT)),
	EXTENSION_LIST(X)
#undef X
};

constexpr u64 INT_EXT_COUNT = sizeof(INT_EXT_NAMES) / sizeof(INT_EXT_NAMES[0]);

inline void int_print_enabled_extensions(u32 mask) {
	bool first = true;
	for(u32 i = 0; i < INT_EXT_COUNT; ++i) {
		if(mask & INT_EXT_BITS[i]) {
			std::printf("%s%s", first ? "" : ", ", INT_EXT_NAMES[i]);
			first = false;
		}
	}
}

// extensions
#include "ext/rv32i/opcodes.def"
#include "ext/rv32m/opcodes.def"
#include "ext/rv64i/opcodes.def"
#include "ext/rv64m/opcodes.def"

#define EXT_OPCODE_LIST(X)                                                                         \
	EXT_RV32I_OPCODES(X)                                                                             \
	EXT_RV64I_OPCODES(X)                                                                             \
	EXT_RV32M_OPCODES(X)                                                                             \
	EXT_RV64M_OPCODES(X)

typedef enum int_opcode : u16 {
#define X(TAG, mnemonic, shape, comm) OP_##TAG,
	EXT_OPCODE_LIST(X)
#undef X
		OP_NOP,
	OP_COUNT,
} int_opcode;

typedef struct int_inst {
	union operand {
		int_reg_index reg;
		u64 i;
	};
	int_opcode op;
	operand operands[4];
} int_inst;

typedef struct int_inst_spec {
	enum operand : u8 {
		NONE = 0,
		REG,
		IMM,
	};

	const char* name;
	operand operands[4];
	int_opcode op;
	i8 dst_slot;
	i8 src_slot;
	i8 src2_slot;
	u32 ext;
	u8 commutative;

	SO_HD constexpr u8 get_operand_count() const {
		u8 i = 0;

		for(; i < 4; ++i) {
			if(operands[i] == NONE) { break; }
		}

		return i;
	}
} int_inst_spec;

typedef struct int_inst_db {
	int_inst_spec row[OP_COUNT];
} int_inst_db;

SO_HD constexpr int_inst_spec::operand int_shape_op0(int_inst_shape s) {
	return s == SHAPE_NONE ? int_inst_spec::NONE : int_inst_spec::REG;
}

SO_HD constexpr int_inst_spec::operand int_shape_op1(int_inst_shape s) {
	switch(s) {
		case SHAPE_RRR:
		case SHAPE_RRI:
		case SHAPE_RR: return int_inst_spec::REG;
		case SHAPE_RI: return int_inst_spec::IMM;
		default: return int_inst_spec::NONE;
	}
}

SO_HD constexpr int_inst_spec::operand int_shape_op2(int_inst_shape s) {
	switch(s) {
		case SHAPE_RRR: return int_inst_spec::REG;
		case SHAPE_RRI: return int_inst_spec::IMM;
		default: return int_inst_spec::NONE;
	}
}

SO_HD constexpr i8 int_shape_dst_slot(int_inst_shape s) { return s == SHAPE_NONE ? (i8)-1 : (i8)0; }

SO_HD constexpr i8 int_shape_src_slot(int_inst_shape s) {
	switch(s) {
		case SHAPE_RRR:
		case SHAPE_RRI:
		case SHAPE_RR: return 1;
		default: return -1;
	}
}

SO_HD constexpr i8 int_shape_src2_slot(int_inst_shape s) { return s == SHAPE_RRR ? (i8)2 : (i8)-1; }

SO_HD constexpr int_inst_db int_build_inst_db() {
	int_inst_db d = {};

#define ROW(TAG, MN, SHAPE, COMM, EXT_BIT)                                                         \
	d.row[OP_##TAG] = int_inst_spec{                                                                 \
		MN,                                                                                            \
		{int_shape_op0(SHAPE), int_shape_op1(SHAPE), int_shape_op2(SHAPE), int_inst_spec::NONE},       \
		OP_##TAG,                                                                                      \
		int_shape_dst_slot(SHAPE),                                                                     \
		int_shape_src_slot(SHAPE),                                                                     \
		int_shape_src2_slot(SHAPE),                                                                    \
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
	d.row[OP_NOP] = int_inst_spec{
		"nop",		 {int_inst_spec::NONE, int_inst_spec::NONE, int_inst_spec::NONE, int_inst_spec::NONE},
		OP_NOP,		 -1,
		-1,				 -1,
		EXT_RV32I, 0};
	return d;
}

inline constexpr int_inst_db INT_INST_DB_HOST = int_build_inst_db();

#ifdef __CUDACC__
static __constant__ int_inst_db INT_INST_DB_DEV = int_build_inst_db();
#endif // #ifdef __CUDACC__

SO_HD const int_inst_spec* int_find_spec(int_opcode op) {
#ifdef __CUDA_ARCH__
	return &INT_INST_DB_DEV.row[op];
#else
	return &INT_INST_DB_HOST.row[op];
#endif // #ifdef __CUDA_ARCH__
}

SO_HD constexpr b32 int_check_inst_db_alignment() {
	const int_inst_db d = int_build_inst_db();

	for(u32 i = 0; i < (u32)OP_COUNT; ++i) {
		if((u32)d.row[i].op != i) { return false; }
	}

	return true;
}

static_assert(int_check_inst_db_alignment(), "INST_DB rows must be in opcode-enum order");

#endif // #ifndef INSTRUCTION_CUH
