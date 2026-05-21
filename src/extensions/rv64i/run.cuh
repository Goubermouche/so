#ifndef EXT_RV64I_RUN_CUH
#define EXT_RV64I_RUN_CUH

#include "cpu/instruction.cuh"
#include "extensions/rv32i/run.cuh"

SO_HD b32 ext_rv64i_run(u32 op, u64 regs[32], const Instruction* in) {
	const u32 d = (u32)in->operands[0].reg;

	switch(op) {
		case InstructionOpcode_Addiw:
			ext_rv_wr(regs, d,
								(u64)ext_rv_sext32((u32)regs[in->operands[1].reg] + (u32)in->operands[2].imm));
			return true;
		case InstructionOpcode_Slliw:
			ext_rv_wr(
				regs, d,
				(u64)ext_rv_sext32(((u32)regs[in->operands[1].reg]) << (in->operands[2].imm & 0x1F)));
			return true;
		case InstructionOpcode_Srliw:
			ext_rv_wr(
				regs, d,
				(u64)ext_rv_sext32(((u32)regs[in->operands[1].reg]) >> (in->operands[2].imm & 0x1F)));
			return true;
		case InstructionOpcode_Sraiw:
			ext_rv_wr(regs, d,
								(u64)((i64)((i32)regs[in->operands[1].reg] >> (in->operands[2].imm & 0x1F))));
			return true;
		case InstructionOpcode_Addw:
			ext_rv_wr(
				regs, d,
				(u64)ext_rv_sext32((u32)regs[in->operands[1].reg] + (u32)regs[in->operands[2].reg]));
			return true;
		case InstructionOpcode_Subw:
			ext_rv_wr(
				regs, d,
				(u64)ext_rv_sext32((u32)regs[in->operands[1].reg] - (u32)regs[in->operands[2].reg]));
			return true;
		case InstructionOpcode_Sllw:
			ext_rv_wr(
				regs, d,
				(u64)ext_rv_sext32(((u32)regs[in->operands[1].reg]) << (regs[in->operands[2].reg] & 0x1F)));
			return true;
		case InstructionOpcode_Srlw:
			ext_rv_wr(
				regs, d,
				(u64)ext_rv_sext32(((u32)regs[in->operands[1].reg]) >> (regs[in->operands[2].reg] & 0x1F)));
			return true;
		case InstructionOpcode_Sraw:
			ext_rv_wr(regs, d,
								(u64)((i64)((i32)regs[in->operands[1].reg] >> (regs[in->operands[2].reg] & 0x1F))));
			return true;
	}

	return false;
}

#endif // #ifndef EXT_RV64I_RUN_CUH
