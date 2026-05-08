#ifndef EXT_RV32I_RUN_CUH
#define EXT_RV32I_RUN_CUH

#include "int/instruction.cuh"

namespace sup {
	// sign-extend the low 32 bits of v to 64 bits
	SO_HD i64 rv_sext32(u64 v) {
		return (i64)(i32)(u32)v;
	}

	// write to register file
	SO_HD void rv_wr(u64 regs[32], u32 d, u64 v) {
		regs[d] = v;
		regs[0] = 0;
	}

	SO_HD bool ext_rv32i_run(u32 op, u64 regs[32], const inst& in) {
		const u32 d = (u32)in.operands[0].reg;

		switch(op) {
			case OP_ADD:   rv_wr(regs, d, regs[in.operands[1].reg] + regs[in.operands[2].reg]); return true;
			case OP_SUB:   rv_wr(regs, d, regs[in.operands[1].reg] - regs[in.operands[2].reg]); return true;
			case OP_SLL:   rv_wr(regs, d, regs[in.operands[1].reg] << (regs[in.operands[2].reg] & 0x3F)); return true;
			case OP_SLT:   rv_wr(regs, d, ((i64)regs[in.operands[1].reg] < (i64)regs[in.operands[2].reg]) ? 1 : 0); return true;
			case OP_SLTU:  rv_wr(regs, d, (regs[in.operands[1].reg] < regs[in.operands[2].reg]) ? 1 : 0); return true;
			case OP_XOR:   rv_wr(regs, d, regs[in.operands[1].reg] ^ regs[in.operands[2].reg]); return true;
			case OP_SRL:   rv_wr(regs, d, regs[in.operands[1].reg] >> (regs[in.operands[2].reg] & 0x3F)); return true;
			case OP_SRA:   rv_wr(regs, d, (u64)((i64)regs[in.operands[1].reg] >> (regs[in.operands[2].reg] & 0x3F))); return true;
			case OP_OR:    rv_wr(regs, d, regs[in.operands[1].reg] | regs[in.operands[2].reg]); return true;
			case OP_AND:   rv_wr(regs, d, regs[in.operands[1].reg] & regs[in.operands[2].reg]); return true;
			case OP_ADDI:  rv_wr(regs, d, regs[in.operands[1].reg] + in.operands[2].i); return true;
			case OP_SLTI:  rv_wr(regs, d, ((i64)regs[in.operands[1].reg] < (i64)in.operands[2].i) ? 1 : 0); return true;
			case OP_SLTIU: rv_wr(regs, d, (regs[in.operands[1].reg] < (u64)in.operands[2].i) ? 1 : 0); return true;
			case OP_XORI:  rv_wr(regs, d, regs[in.operands[1].reg] ^ in.operands[2].i); return true;
			case OP_ORI:   rv_wr(regs, d, regs[in.operands[1].reg] | in.operands[2].i); return true;
			case OP_ANDI:  rv_wr(regs, d, regs[in.operands[1].reg] & in.operands[2].i); return true;
			case OP_SLLI:  rv_wr(regs, d, regs[in.operands[1].reg] << (in.operands[2].i & 0x3F)); return true;
			case OP_SRLI:  rv_wr(regs, d, regs[in.operands[1].reg] >> (in.operands[2].i & 0x3F)); return true;
			case OP_SRAI:  rv_wr(regs, d, (u64)((i64)regs[in.operands[1].reg] >> (in.operands[2].i & 0x3F))); return true;
			case OP_LUI:   rv_wr(regs, d, (u64)(i64)(i32)((u32)in.operands[1].i << 12)); return true;
		}

		return false;
	}
} // namespace sup

#endif // #ifndef EXT_RV32I_RUN_CUH

