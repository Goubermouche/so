#ifndef EXT_RV32I_RUN_CUH
#define EXT_RV32I_RUN_CUH

#include "cpu/instruction.cuh"

// sign-extend the low 32 bits of v to 64 bits
HostDevice I64 ext_rv_sext32(U64 v) { return (I64)(I32)(U32)v; }

// write to register file
HostDevice void ext_rv_wr(U64 regs[32], U32 d, U64 v) {
	regs[d] = v;
	regs[0] = 0;
}

HostDevice B32 ext_rv32i_run(U32 op, U64 regs[32], Instruction* in) {
	U32 d = (U32)in->operands[0].reg;

	switch(op) {
		case InstructionOpcode_Add:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] + regs[in->operands[2].reg]);
			return true;
		case InstructionOpcode_Sub:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] - regs[in->operands[2].reg]);
			return true;
		case InstructionOpcode_Sll:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] << (regs[in->operands[2].reg] & 0x3F));
			return true;
		case InstructionOpcode_Slt:
			ext_rv_wr(regs, d, ((I64)regs[in->operands[1].reg] < (I64)regs[in->operands[2].reg]) ? 1 : 0);
			return true;
		case InstructionOpcode_Sltu:
			ext_rv_wr(regs, d, (regs[in->operands[1].reg] < regs[in->operands[2].reg]) ? 1 : 0);
			return true;
		case InstructionOpcode_Xor:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] ^ regs[in->operands[2].reg]);
			return true;
		case InstructionOpcode_Srl:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] >> (regs[in->operands[2].reg] & 0x3F));
			return true;
		case InstructionOpcode_Sra:
			ext_rv_wr(regs, d,
								(U64)((I64)regs[in->operands[1].reg] >> (regs[in->operands[2].reg] & 0x3F)));
			return true;
		case InstructionOpcode_Or:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] | regs[in->operands[2].reg]);
			return true;
		case InstructionOpcode_And:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] & regs[in->operands[2].reg]);
			return true;
		case InstructionOpcode_Addi:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] + in->operands[2].imm);
			return true;
		case InstructionOpcode_Slti:
			ext_rv_wr(regs, d, ((I64)regs[in->operands[1].reg] < (I64)in->operands[2].imm) ? 1 : 0);
			return true;
		case InstructionOpcode_Sltiu:
			ext_rv_wr(regs, d, (regs[in->operands[1].reg] < (U64)in->operands[2].imm) ? 1 : 0);
			return true;
		case InstructionOpcode_Xori:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] ^ in->operands[2].imm);
			return true;
		case InstructionOpcode_Ori:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] | in->operands[2].imm);
			return true;
		case InstructionOpcode_Andi:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] & in->operands[2].imm);
			return true;
		case InstructionOpcode_Slli:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] << (in->operands[2].imm & 0x3F));
			return true;
		case InstructionOpcode_Srli:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] >> (in->operands[2].imm & 0x3F));
			return true;
		case InstructionOpcode_Srai:
			ext_rv_wr(regs, d, (U64)((I64)regs[in->operands[1].reg] >> (in->operands[2].imm & 0x3F)));
			return true;
		case InstructionOpcode_Lui:
			ext_rv_wr(regs, d, (U64)(I64)(I32)((U32)in->operands[1].imm << 12));
			return true;
	}

	return false;
}

#endif // #ifndef EXT_RV32I_RUN_CUH
