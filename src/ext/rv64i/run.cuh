#ifndef EXT_RV64I_RUN_CUH
#define EXT_RV64I_RUN_CUH

#include "int/instruction.cuh"
#include "ext/rv32i/run.cuh"

namespace sup {
	SO_HD bool ext_rv64i_run(u32 op, u64 regs[32], const inst& in) {
		const u32 d = (u32)in.operands[0].reg;

		switch(op) {
			case OP_ADDIW: rv_wr(regs, d, (u64)rv_sext32((u32)regs[in.operands[1].reg] + (u32)in.operands[2].i)); return true;
			case OP_SLLIW: rv_wr(regs, d, (u64)rv_sext32(((u32)regs[in.operands[1].reg]) << (in.operands[2].i & 0x1F))); return true;
			case OP_SRLIW: rv_wr(regs, d, (u64)rv_sext32(((u32)regs[in.operands[1].reg]) >> (in.operands[2].i & 0x1F))); return true;
			case OP_SRAIW: rv_wr(regs, d, (u64)((i64)((i32)regs[in.operands[1].reg] >> (in.operands[2].i & 0x1F)))); return true;
			case OP_ADDW:  rv_wr(regs, d, (u64)rv_sext32((u32)regs[in.operands[1].reg] + (u32)regs[in.operands[2].reg])); return true;
			case OP_SUBW:  rv_wr(regs, d, (u64)rv_sext32((u32)regs[in.operands[1].reg] - (u32)regs[in.operands[2].reg])); return true;
			case OP_SLLW:  rv_wr(regs, d, (u64)rv_sext32(((u32)regs[in.operands[1].reg]) << (regs[in.operands[2].reg] & 0x1F))); return true;
			case OP_SRLW:  rv_wr(regs, d, (u64)rv_sext32(((u32)regs[in.operands[1].reg]) >> (regs[in.operands[2].reg] & 0x1F))); return true;
			case OP_SRAW:  rv_wr(regs, d, (u64)((i64)((i32)regs[in.operands[1].reg] >> (regs[in.operands[2].reg] & 0x1F)))); return true;
		}

		return false;
	}
} // namespace sup

#endif // #ifndef EXT_RV64I_RUN_CUH

