#ifndef EXT_RV32I_RUN_CUH
#define EXT_RV32I_RUN_CUH

#include "cpu/instruction.cuh"

// sign-extend the low 32 bits of v to 64 bits
SO_HD i64 ext_rv_sext32(u64 v) { return (i64)(i32)(u32)v; }

// write to register file
SO_HD void ext_rv_wr(u64 regs[32], u32 d, u64 v) {
	regs[d] = v;
	regs[0] = 0;
}

SO_HD b32 ext_rv32i_run(u32 op, u64 regs[32], const Instruction* in) {
	const u32 d = (u32)in->operands[0].reg;

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
			ext_rv_wr(regs, d, ((i64)regs[in->operands[1].reg] < (i64)regs[in->operands[2].reg]) ? 1 : 0);
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
								(u64)((i64)regs[in->operands[1].reg] >> (regs[in->operands[2].reg] & 0x3F)));
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
			ext_rv_wr(regs, d, ((i64)regs[in->operands[1].reg] < (i64)in->operands[2].imm) ? 1 : 0);
			return true;
		case InstructionOpcode_Sltiu:
			ext_rv_wr(regs, d, (regs[in->operands[1].reg] < (u64)in->operands[2].imm) ? 1 : 0);
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
			ext_rv_wr(regs, d, (u64)((i64)regs[in->operands[1].reg] >> (in->operands[2].imm & 0x3F)));
			return true;
		case InstructionOpcode_Lui:
			ext_rv_wr(regs, d, (u64)(i64)(i32)((u32)in->operands[1].imm << 12));
			return true;
	}

	return false;
}

#endif // #ifndef EXT_RV32I_RUN_CUH
