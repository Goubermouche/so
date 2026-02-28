#ifndef INSTRUCTION_CUH
#define INSTRUCTION_CUH

#include "utility/type.h"

namespace so {
	// registers
	constexpr u8 REG_COUNT = 2;

	enum register_type {
		REG_EAX,
		REG_EBX
	};
	enum inst_op : u8 {
		OP_N = 0,
		OP_R = 0b01,
		OP_I = 0b10
	};

	enum inst_opcode : u16 {
		INST_MOV,
		INST_SUB,
		INST_NOT,
		INST_AND,
		INST_NEG,
	};

	enum inst_tag : u32;

	constexpr inst_tag encode_tag(inst_opcode opcode, inst_op op0 = OP_N, inst_op op1 = OP_N) {
		u32 count = (op0 != OP_N) + (op1 != OP_N);
		return (inst_tag)((opcode << 7) | (count << 4) | (op0 << 2) | op1);
	}

	constexpr inst_opcode tag_opcode(inst_tag t) {
		return (inst_opcode)(t >> 7);
	}

	constexpr u32 tag_op_count(inst_tag t) {
		return (t >> 4) & 0x7;
	}

	constexpr inst_op tag_op(inst_tag t, u32 i) {
		return (inst_op)((t >> (2 * (1 - i))) & 0x3);
	}

	struct inst_variant {
		constexpr inst_variant(
			const char* name,
			inst_tag tag
		) :
			name(name),
			tag(tag)
		{
			operands[0] = tag_op(tag, 0);
			operands[1] = tag_op(tag, 1);
			operands[2] = OP_N;
			operands[3] = OP_N;
		}

		const char* name = nullptr;
		inst_op operands[4] = {};
		inst_tag tag = {};
	};

	enum inst_tag : u32 {
		// 16b opcode | 3b operand count | 2b op0 | 2b op1
		INST_MOV_RR = encode_tag(INST_MOV, OP_R, OP_R),
		INST_SUB_RI = encode_tag(INST_SUB, OP_R, OP_I),
		INST_SUB_RR = encode_tag(INST_SUB, OP_R, OP_R),
		INST_NOT_R  = encode_tag(INST_NOT, OP_R),
		INST_AND_RR = encode_tag(INST_AND, OP_R, OP_R),
		INST_NEG_R  = encode_tag(INST_NEG, OP_R),
	};

	constexpr inst_variant INSTRUCTION_DB[] = {
		inst_variant("mov", INST_MOV_RR),
		inst_variant("sub", INST_SUB_RI),
		inst_variant("sub", INST_SUB_RR),
		inst_variant("not", INST_NOT_R),
		inst_variant("and", INST_AND_RR),
		inst_variant("neg", INST_NEG_R),
	};

	constexpr u32 INSTRUCTION_DB_SIZE = sizeof(INSTRUCTION_DB) / sizeof(INSTRUCTION_DB[0]);

	inline auto find_inst_tag(const str& name, const inst_op(&operands)[4], u8 operand_count) -> inst_tag {
		for(u32 i = 0; i < INSTRUCTION_DB_SIZE; ++i) {
			if(strcmp(INSTRUCTION_DB[i].name, name.c_str()) != 0) {
				continue; // not a name match
			}

			// name matches, match operands
			while(strcmp(INSTRUCTION_DB[i].name, name.c_str()) == 0) {
				if(memcmp(operands, INSTRUCTION_DB[i].operands, sizeof(inst_op) * 4) == 0) {
					// found match
					return INSTRUCTION_DB[i].tag;
				}
			}

			ASSERT(false, "unknown operand combination for '{}'\n", name);
		}

		ASSERT(false, "unknown instruction '{}'\n", name);
		return {};
	}

	struct inst {
		void print() const {
			// TODO
			for(u32 i = 0; i < INSTRUCTION_DB_SIZE; ++i) {
				if(INSTRUCTION_DB[i].tag == tag) {
					so::print("  {}   ", INSTRUCTION_DB[i].name);
				}
			}

			u8 operand_count = tag_op_count(tag);
			for(u8 i = 0; i < operand_count; ++i) {
				switch(tag_op(tag, i)) {
					case OP_R: {
						const char* regs[] = { "eax", "ebx" };
						so::print("{}", regs[ops[i]]);
						break;
					}
					case OP_I: {
						so::print("{}", ops[i]);
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

		inst_tag tag;
		u64 ops[2];
	};
} // namespace so

#endif // #ifndef INSTRUCTION_CUH

