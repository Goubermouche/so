#ifndef INSTRUCTION_CUH
#define INSTRUCTION_CUH

#include "int/cpu.cuh"

// to add a new extension:
// - create src/ext/<name>/ext.cuh defining the X-macro and the run handler
// - #include it below and append it to the EXT_OPCODE_LIST and ext_bits enum
// - add a Z3.cc file that exposes ext_<name>_smt(...)
// - wire those into smt/smt.cc and opt/batch_runner.cuh's dispatcher

namespace sup {
	enum inst_shape : u8 {
		SHAPE_NONE = 0, // nop
		SHAPE_RRR,      // rd, rs1, rs2
		SHAPE_RRI,      // rd, rs1, imm
		SHAPE_RR,       // rd, rs1
		SHAPE_RI,       // rd, imm
	};

	// EXT_RV32I is the base ISA and is always implied
	// rv64-prefixed extensions extend their rv32 counterpart and require
	// it to be enabled. The optimizer's pool builder enforces this implicitly
	enum ext_bits : u32 {
		EXT_RV32I = 1u << 0,
		EXT_RV64I = 1u << 1,
		EXT_RV32M = 1u << 2,
		EXT_RV64M = 1u << 3,
	};
} // namespace sup

// extensions
#include "ext/rv32i/opcodes.def"
#include "ext/rv64i/opcodes.def"
#include "ext/rv32m/opcodes.def"
#include "ext/rv64m/opcodes.def"

namespace sup {
#define EXT_OPCODE_LIST(X) \
	EXT_RV32I_OPCODES(X)     \
	EXT_RV64I_OPCODES(X)     \
	EXT_RV32M_OPCODES(X)     \
	EXT_RV64M_OPCODES(X)

	enum opcode : u16 {
#define X(TAG, mnemonic, shape, comm) OP_##TAG,
		EXT_OPCODE_LIST(X)
#undef X
		OP_NOP,
		OP_COUNT,
	};

	struct inst {
		union operand {
			reg_index reg;
			u64 i;
		};
		opcode op;
		operand operands[4];
	};

	struct inst_spec {
		enum operand : u8 {
			NONE = 0,
			REG,
			IMM,
		};

		const char* name;
		operand operands[4];
		opcode op;
		i8 dst_slot;
		i8 src_slot;
		i8 src2_slot;
		u32 ext;
		u8 commutative;

		SO_HD constexpr u8 get_operand_count() const {
			u8 i = 0;

			for(; i < 4; ++i) {
				if(operands[i] == NONE) {
					break;
				}
			}

			return i;
		}
	};

	struct inst_db_t {
		inst_spec row[OP_COUNT];
	};

	SO_HD constexpr inst_spec::operand shape_op0(inst_shape s) {
		return s == SHAPE_NONE ? inst_spec::NONE : inst_spec::REG;
	}

	SO_HD constexpr inst_spec::operand shape_op1(inst_shape s) {
		switch(s) {
			case SHAPE_RRR: case SHAPE_RRI: case SHAPE_RR: return inst_spec::REG;
			case SHAPE_RI:                                 return inst_spec::IMM;
			default:                                       return inst_spec::NONE;
		}
	}

	SO_HD constexpr inst_spec::operand shape_op2(inst_shape s) {
		switch(s) {
			case SHAPE_RRR: return inst_spec::REG;
			case SHAPE_RRI: return inst_spec::IMM;
			default:        return inst_spec::NONE;
		}
	}

	SO_HD constexpr i8 shape_dst_slot(inst_shape s) {
		return s == SHAPE_NONE ? (i8)-1 : (i8)0;
	}

	SO_HD constexpr i8 shape_src_slot(inst_shape s) {
		switch(s) {
			case SHAPE_RRR: case SHAPE_RRI: case SHAPE_RR: return 1;
			default:                                       return -1;
		}
	}

	SO_HD constexpr i8 shape_src2_slot(inst_shape s) {
		return s == SHAPE_RRR ? (i8)2 : (i8)-1;
	}

	SO_HD constexpr inst_db_t build_inst_db() {
		inst_db_t d = {};

#define ROW(TAG, MN, SHAPE, COMM, EXT_BIT)                                     \
	d.row[OP_##TAG] = inst_spec{                                                 \
		MN,                                                                        \
		{ shape_op0(SHAPE), shape_op1(SHAPE), shape_op2(SHAPE), inst_spec::NONE }, \
		OP_##TAG,                                                                  \
		shape_dst_slot(SHAPE),                                                     \
		shape_src_slot(SHAPE),                                                     \
		shape_src2_slot(SHAPE),                                                    \
		(u32)(EXT_BIT),                                                            \
		(u8)(COMM)                                                                 \
	};

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
		d.row[OP_NOP] = inst_spec{
			"nop",
			{ inst_spec::NONE, inst_spec::NONE, inst_spec::NONE, inst_spec::NONE },
			OP_NOP, -1, -1, -1, EXT_RV32I, 0
		};
		return d;
	}

	inline constexpr inst_db_t INST_DB_HOST = build_inst_db();

#ifdef __CUDACC__
	static __constant__ inst_db_t INST_DB_DEV = build_inst_db();
#endif // #ifdef __CUDACC__

	SO_HD const inst_spec& find_spec(opcode op) {
#ifdef __CUDA_ARCH__
		return INST_DB_DEV.row[op];
#else
		return INST_DB_HOST.row[op];
#endif // #ifdef __CUDA_ARCH__
	}

	namespace detail {
		SO_HD constexpr b32 check_inst_db_alignment() {
			const inst_db_t d = build_inst_db();

			for(u32 i = 0; i < (u32)OP_COUNT; ++i) {
				if((u32)d.row[i].op != i) {
					return false;
				}
			}

			return true;
		}

		static_assert(check_inst_db_alignment(), "INST_DB rows must be in opcode-enum order");
	} // namespace detail
} // namespace sup

#endif // #ifndef INSTRUCTION_CUH

