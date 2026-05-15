#ifndef EXT_RV64I_RUN_CUH
#define EXT_RV64I_RUN_CUH

#include "extensions/rv32i/run.cuh"
#include "cpu/instruction.cuh"

SO_HD bool ext_rv64i_run(u32 op, u64 regs[32], const cpu_inst* in) {
	const u32 d = (u32)in->operands[0].reg;

	switch(op) {
		case OP_ADDIW:
			ext_rv_wr(regs, d,
								(u64)ext_rv_sext32((u32)regs[in->operands[1].reg] + (u32)in->operands[2].i));
			return true;
		case OP_SLLIW:
			ext_rv_wr(regs, d,
								(u64)ext_rv_sext32(((u32)regs[in->operands[1].reg]) << (in->operands[2].i & 0x1F)));
			return true;
		case OP_SRLIW:
			ext_rv_wr(regs, d,
								(u64)ext_rv_sext32(((u32)regs[in->operands[1].reg]) >> (in->operands[2].i & 0x1F)));
			return true;
		case OP_SRAIW:
			ext_rv_wr(regs, d,
								(u64)((i64)((i32)regs[in->operands[1].reg] >> (in->operands[2].i & 0x1F))));
			return true;
		case OP_ADDW:
			ext_rv_wr(
				regs, d,
				(u64)ext_rv_sext32((u32)regs[in->operands[1].reg] + (u32)regs[in->operands[2].reg]));
			return true;
		case OP_SUBW:
			ext_rv_wr(
				regs, d,
				(u64)ext_rv_sext32((u32)regs[in->operands[1].reg] - (u32)regs[in->operands[2].reg]));
			return true;
		case OP_SLLW:
			ext_rv_wr(
				regs, d,
				(u64)ext_rv_sext32(((u32)regs[in->operands[1].reg]) << (regs[in->operands[2].reg] & 0x1F)));
			return true;
		case OP_SRLW:
			ext_rv_wr(
				regs, d,
				(u64)ext_rv_sext32(((u32)regs[in->operands[1].reg]) >> (regs[in->operands[2].reg] & 0x1F)));
			return true;
		case OP_SRAW:
			ext_rv_wr(regs, d,
								(u64)((i64)((i32)regs[in->operands[1].reg] >> (regs[in->operands[2].reg] & 0x1F))));
			return true;
	}

	return false;
}

#endif // #ifndef EXT_RV64I_RUN_CUH
