#ifndef INSTRUCTION_CUH
#define INSTRUCTION_CUH

#include "utility/type.h"

namespace so {
	// registers
	constexpr u8 REG_COUNT = 6;
	constexpr u32 MAX_PROG_LEN = 8;

	struct reg {
		enum type : u8 {
			EAX = 0,
			EBX,
			ECX,
			EDX,
			ESI,
			EDI,
		};

		reg() = default;
		HD reg(u8 index) : m_type(static_cast<type>(index)) {}
		HD operator u8() const { return static_cast<u8>(m_type); }
		HD const char* to_string() const {
			constexpr const char* names[] = { "eax", "ebx", "ecx", "edx", "esi", "edi" };
			return names[m_type];
		}
	private:
		type m_type;
	};

	enum inst_op : u8 {
		OP_N = 0,
		OP_R = 0b01,
		OP_I = 0b10
	};

	struct inst_desc {
		u8 op_count() const {
			u32 n = 0;

			for(u32 i = 0; i < 4; ++i) {
				if(operands[i] != OP_N) {
					++n;
				}
			}

			return n;
		}

		const char* name;
		inst_op operands[4];
	};

#define INST_LIST                                                              \
	X(INST_MOV_RR,  "mov",  OP_R, OP_R, OP_N, OP_N, { dst = state.regs[ins.ops[1].r]; })  \
	X(INST_MOV_RI,  "mov",  OP_R, OP_I, OP_N, OP_N, { dst = ins.ops[1].i; })              \
	X(INST_ADD_RR,  "add",  OP_R, OP_R, OP_N, OP_N, { dst += state.regs[ins.ops[1].r]; }) \
	X(INST_ADD_RI,  "add",  OP_R, OP_I, OP_N, OP_N, { dst += ins.ops[1].i; })             \
	X(INST_SUB_RR,  "sub",  OP_R, OP_R, OP_N, OP_N, { dst -= state.regs[ins.ops[1].r]; }) \
	X(INST_SUB_RI,  "sub",  OP_R, OP_I, OP_N, OP_N, { dst -= ins.ops[1].i; })             \
	X(INST_MUL_RR,  "mul",  OP_R, OP_R, OP_N, OP_N, { dst *= state.regs[ins.ops[1].r]; }) \
	X(INST_MUL_RI,  "mul",  OP_R, OP_I, OP_N, OP_N, { dst *= ins.ops[1].i; })             \
	X(INST_AND_RR,  "and",  OP_R, OP_R, OP_N, OP_N, { dst &= state.regs[ins.ops[1].r]; }) \
	X(INST_AND_RI,  "and",  OP_R, OP_I, OP_N, OP_N, { dst &= ins.ops[1].i; })             \
	X(INST_OR_RR,   "or",   OP_R, OP_R, OP_N, OP_N, { dst |= state.regs[ins.ops[1].r]; }) \
	X(INST_OR_RI,   "or",   OP_R, OP_I, OP_N, OP_N, { dst |= ins.ops[1].i; })             \
	X(INST_XOR_RR,  "xor",  OP_R, OP_R, OP_N, OP_N, { dst ^= state.regs[ins.ops[1].r]; }) \
	X(INST_XOR_RI,  "xor",  OP_R, OP_I, OP_N, OP_N, { dst ^= ins.ops[1].i; })             \
	X(INST_SHL_RR,  "shl",  OP_R, OP_R, OP_N, OP_N, { dst <<= (state.regs[ins.ops[1].r] & 31); }) \
	X(INST_SHL_RI,  "shl",  OP_R, OP_I, OP_N, OP_N, { dst <<= (ins.ops[1].i & 31); })     \
	X(INST_SHR_RR,  "shr",  OP_R, OP_R, OP_N, OP_N, { dst >>= (state.regs[ins.ops[1].r] & 31); }) \
	X(INST_SHR_RI,  "shr",  OP_R, OP_I, OP_N, OP_N, { dst >>= (ins.ops[1].i & 31); })     \
	X(INST_SAR_RR,  "sar",  OP_R, OP_R, OP_N, OP_N, { dst = (u32)((i32)dst >> (state.regs[ins.ops[1].r] & 31)); }) \
	X(INST_SAR_RI,  "sar",  OP_R, OP_I, OP_N, OP_N, { dst = (u32)((i32)dst >> (ins.ops[1].i & 31)); }) \
	X(INST_ROL_RI,  "rol",  OP_R, OP_I, OP_N, OP_N, { u32 s = ins.ops[1].i & 31; dst = (dst << s) | (dst >> (32 - s)); }) \
	X(INST_ROR_RI,  "ror",  OP_R, OP_I, OP_N, OP_N, { u32 s = ins.ops[1].i & 31; dst = (dst >> s) | (dst << (32 - s)); }) \
	X(INST_NOT_R,   "not",  OP_R, OP_N, OP_N, OP_N, { dst = ~dst; })                      \
	X(INST_NEG_R,   "neg",  OP_R, OP_N, OP_N, OP_N, { dst = (u32)(-(i32)dst); })          \
	X(INST_INC_R,   "inc",  OP_R, OP_N, OP_N, OP_N, { dst++; })                           \
	X(INST_DEC_R,   "dec",  OP_R, OP_N, OP_N, OP_N, { dst--; })                           \
	X(INST_XCHG_RR, "xchg", OP_R, OP_R, OP_N, OP_N, { u32 t = dst; dst = state.regs[ins.ops[1].r]; state.regs[ins.ops[1].r] = t; }) \
	X(INST_IMUL_RR, "imul", OP_R, OP_R, OP_N, OP_N, { dst = (u32)((i32)dst * (i32)state.regs[ins.ops[1].r]); }) \
	X(INST_IMUL_RI, "imul", OP_R, OP_I, OP_N, OP_N, { dst = (u32)((i32)dst * (i32)ins.ops[1].i); }) \
	X(INST_IMUL_RRI,"imul", OP_R, OP_R, OP_I, OP_N, { dst = (u32)((i32)state.regs[ins.ops[1].r] * (i32)ins.ops[2].i); }) \
	X(INST_LEA_RRI, "lea",  OP_R, OP_R, OP_I, OP_N, { dst = state.regs[ins.ops[1].r] + ins.ops[2].i; })

	// generate instruction id enum
	enum inst_id : u32 {
#define X(id, name, op1, op2, op3, op4, body) id,
		INST_LIST
#undef X
		INST_ID_COUNT
	};

	// generate instruction table
	constexpr inst_desc INSTRUCTION_DB[] = {
#define X(id, name, op1, op2, op3, op4, body) {name, {op1, op2, op3, op4}},
		INST_LIST
#undef X
	};

	constexpr u32 INSTRUCTION_DB_SIZE = sizeof(INSTRUCTION_DB) / sizeof(INSTRUCTION_DB[0]);
	static_assert(INSTRUCTION_DB_SIZE == INST_ID_COUNT, "INST_LIST out of sync");

	inline auto find_inst_tag(const str& name, const inst_op(&operands)[4], u8 operand_count) -> inst_id {
		for(u32 i = 0; i < INSTRUCTION_DB_SIZE; ++i) {
			if(strcmp(INSTRUCTION_DB[i].name, name.c_str()) != 0) {
				continue; // not a name match
			}

			// name matches, match operands
			while(strcmp(INSTRUCTION_DB[i].name, name.c_str()) == 0) {
				if(memcmp(operands, INSTRUCTION_DB[i].operands, sizeof(inst_op) * 4) == 0) {
					// found match
					return static_cast<inst_id>(i);
				}
				++i;
			}

			ASSERT(false, "unknown operand combination for '{}'\n", name);
		}

		ASSERT(false, "unknown instruction '{}'\n", name);
		return {};
	}

	struct inst {
		void print() const {
			const inst_desc& desc = INSTRUCTION_DB[id];
			so::print("  {}   ", desc.name);

			u8 operand_count = desc.op_count();
			for(u8 i = 0; i < operand_count; ++i) {
				switch(desc.operands[i]) {
					case OP_R: {
						so::print("{}", ops[i].r.to_string());
						break;
					}
					case OP_I: {
						so::print("{}", ops[i].i);
						break;
					}
					default: ASSERT(false, "");
				}

				if(i + 1 < operand_count) {
					so::print(", ");
				}
			}
			so::print("\n");
		}

		inst_id id;

		union {
			reg r;
			u32 i;
		} ops[4];
	};
} // namespace so

#endif // #ifndef INSTRUCTION_CUH

