#ifndef INSTRUCTION_CUH
#define INSTRUCTION_CUH

#include "int/cpu.cuh"

namespace sup {
	enum opcode : u16 {
		OP_MOV_R64_R64 = 0,
		OP_MOV_R64_I64,
		OP_ADD_R64_R64,
		OP_ADD_R64_I64,
		OP_SUB_R64_R64,
		OP_SUB_R64_I64,
		OP_NEG_R64,
		OP_IMUL_R64_R64,
		OP_IMUL_R64_I64,
		OP_AND_R64_R64,
		OP_AND_R64_I64,
		OP_OR_R64_R64,
		OP_OR_R64_I64,
		OP_XOR_R64_R64,
		OP_XOR_R64_I64,
		OP_NOT_R64,
		OP_SHL_R64_I64,
		OP_SHR_R64_I64,
		OP_SAR_R64_I64,
		OP_ROL_R64_I64,
		OP_ROR_R64_I64,
		OP_LEA_R64_R64_R64_S1,
		OP_LEA_R64_R64_R64_S2,
		OP_LEA_R64_R64_R64_S4,
		OP_LEA_R64_R64_R64_S8,
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
			R64,
			I64,
		};

		const char* name;
		operand operands[4];
		opcode op;
		i8 dst_slot;
		i8 src_slot;
		i8 src2_slot;
		b32 rmw; // dst is also a read

		SO_HD constexpr u8 get_operand_count() const {
			u8 i = 0;
			for(; i < 4; ++i) {
				if(operands[i] == NONE) break;
			}
			return i;
		}
	};

	struct inst_db_t {
		inst_spec row[OP_COUNT];
	};

	SO_HD constexpr inst_db_t build_inst_db() {
		inst_db_t d = {};
		d.row[OP_MOV_R64_R64       ] = { "mov",  { inst_spec::R64, inst_spec::R64,  inst_spec::NONE, inst_spec::NONE }, OP_MOV_R64_R64,        0,  1, -1, false };
		d.row[OP_MOV_R64_I64       ] = { "mov",  { inst_spec::R64, inst_spec::I64,  inst_spec::NONE, inst_spec::NONE }, OP_MOV_R64_I64,        0, -1, -1, false };
		d.row[OP_ADD_R64_R64       ] = { "add",  { inst_spec::R64, inst_spec::R64,  inst_spec::NONE, inst_spec::NONE }, OP_ADD_R64_R64,        0,  1, -1, true  };
		d.row[OP_ADD_R64_I64       ] = { "add",  { inst_spec::R64, inst_spec::I64,  inst_spec::NONE, inst_spec::NONE }, OP_ADD_R64_I64,        0, -1, -1, true  };
		d.row[OP_SUB_R64_R64       ] = { "sub",  { inst_spec::R64, inst_spec::R64,  inst_spec::NONE, inst_spec::NONE }, OP_SUB_R64_R64,        0,  1, -1, true  };
		d.row[OP_SUB_R64_I64       ] = { "sub",  { inst_spec::R64, inst_spec::I64,  inst_spec::NONE, inst_spec::NONE }, OP_SUB_R64_I64,        0, -1, -1, true  };
		d.row[OP_NEG_R64           ] = { "neg",  { inst_spec::R64, inst_spec::NONE, inst_spec::NONE, inst_spec::NONE }, OP_NEG_R64,            0, -1, -1, true  };
		d.row[OP_IMUL_R64_R64      ] = { "imul", { inst_spec::R64, inst_spec::R64,  inst_spec::NONE, inst_spec::NONE }, OP_IMUL_R64_R64,       0,  1, -1, true  };
		d.row[OP_IMUL_R64_I64      ] = { "imul", { inst_spec::R64, inst_spec::I64,  inst_spec::NONE, inst_spec::NONE }, OP_IMUL_R64_I64,       0, -1, -1, true  };
		d.row[OP_AND_R64_R64       ] = { "and",  { inst_spec::R64, inst_spec::R64,  inst_spec::NONE, inst_spec::NONE }, OP_AND_R64_R64,        0,  1, -1, true  };
		d.row[OP_AND_R64_I64       ] = { "and",  { inst_spec::R64, inst_spec::I64,  inst_spec::NONE, inst_spec::NONE }, OP_AND_R64_I64,        0, -1, -1, true  };
		d.row[OP_OR_R64_R64        ] = { "or",   { inst_spec::R64, inst_spec::R64,  inst_spec::NONE, inst_spec::NONE }, OP_OR_R64_R64,         0,  1, -1, true  };
		d.row[OP_OR_R64_I64        ] = { "or",   { inst_spec::R64, inst_spec::I64,  inst_spec::NONE, inst_spec::NONE }, OP_OR_R64_I64,         0, -1, -1, true  };
		d.row[OP_XOR_R64_R64       ] = { "xor",  { inst_spec::R64, inst_spec::R64,  inst_spec::NONE, inst_spec::NONE }, OP_XOR_R64_R64,        0,  1, -1, true  };
		d.row[OP_XOR_R64_I64       ] = { "xor",  { inst_spec::R64, inst_spec::I64,  inst_spec::NONE, inst_spec::NONE }, OP_XOR_R64_I64,        0, -1, -1, true  };
		d.row[OP_NOT_R64           ] = { "not",  { inst_spec::R64, inst_spec::NONE, inst_spec::NONE, inst_spec::NONE }, OP_NOT_R64,            0, -1, -1, true  };
		d.row[OP_SHL_R64_I64       ] = { "shl",  { inst_spec::R64, inst_spec::I64,  inst_spec::NONE, inst_spec::NONE }, OP_SHL_R64_I64,        0, -1, -1, true  };
		d.row[OP_SHR_R64_I64       ] = { "shr",  { inst_spec::R64, inst_spec::I64,  inst_spec::NONE, inst_spec::NONE }, OP_SHR_R64_I64,        0, -1, -1, true  };
		d.row[OP_SAR_R64_I64       ] = { "sar",  { inst_spec::R64, inst_spec::I64,  inst_spec::NONE, inst_spec::NONE }, OP_SAR_R64_I64,        0, -1, -1, true  };
		d.row[OP_ROL_R64_I64       ] = { "rol",  { inst_spec::R64, inst_spec::I64,  inst_spec::NONE, inst_spec::NONE }, OP_ROL_R64_I64,        0, -1, -1, true  };
		d.row[OP_ROR_R64_I64       ] = { "ror",  { inst_spec::R64, inst_spec::I64,  inst_spec::NONE, inst_spec::NONE }, OP_ROR_R64_I64,        0, -1, -1, true  };
		d.row[OP_LEA_R64_R64_R64_S1] = { "lea",  { inst_spec::R64, inst_spec::R64,  inst_spec::R64,  inst_spec::NONE }, OP_LEA_R64_R64_R64_S1, 0,  1,  2, false };
		d.row[OP_LEA_R64_R64_R64_S2] = { "lea",  { inst_spec::R64, inst_spec::R64,  inst_spec::R64,  inst_spec::NONE }, OP_LEA_R64_R64_R64_S2, 0,  1,  2, false };
		d.row[OP_LEA_R64_R64_R64_S4] = { "lea",  { inst_spec::R64, inst_spec::R64,  inst_spec::R64,  inst_spec::NONE }, OP_LEA_R64_R64_R64_S4, 0,  1,  2, false };
		d.row[OP_LEA_R64_R64_R64_S8] = { "lea",  { inst_spec::R64, inst_spec::R64,  inst_spec::R64,  inst_spec::NONE }, OP_LEA_R64_R64_R64_S8, 0,  1,  2, false };
		d.row[OP_NOP               ] = { "nop",  { inst_spec::NONE,inst_spec::NONE, inst_spec::NONE, inst_spec::NONE }, OP_NOP,               -1, -1, -1, false };
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
				if((u32)d.row[i].op != i) return false;
			}
			return true;
		}
		static_assert(check_inst_db_alignment(), "INST_DB rows must be in opcode-enum order");
	} //namespace detail
} // namespace sup

#endif // #ifndef INSTRUCTION_CUH

