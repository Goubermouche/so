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

SO_HD bool ext_rv32i_run(u32 op, u64 regs[32], const cpu_inst* in) {
	const u32 d = (u32)in->operands[0].reg;

	switch(op) {
		case OP_ADD:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] + regs[in->operands[2].reg]);
			return true;
		case OP_SUB:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] - regs[in->operands[2].reg]);
			return true;
		case OP_SLL:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] << (regs[in->operands[2].reg] & 0x3F));
			return true;
		case OP_SLT:
			ext_rv_wr(regs, d, ((i64)regs[in->operands[1].reg] < (i64)regs[in->operands[2].reg]) ? 1 : 0);
			return true;
		case OP_SLTU:
			ext_rv_wr(regs, d, (regs[in->operands[1].reg] < regs[in->operands[2].reg]) ? 1 : 0);
			return true;
		case OP_XOR:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] ^ regs[in->operands[2].reg]);
			return true;
		case OP_SRL:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] >> (regs[in->operands[2].reg] & 0x3F));
			return true;
		case OP_SRA:
			ext_rv_wr(regs, d,
								(u64)((i64)regs[in->operands[1].reg] >> (regs[in->operands[2].reg] & 0x3F)));
			return true;
		case OP_OR:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] | regs[in->operands[2].reg]);
			return true;
		case OP_AND:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] & regs[in->operands[2].reg]);
			return true;
		case OP_ADDI: ext_rv_wr(regs, d, regs[in->operands[1].reg] + in->operands[2].i); return true;
		case OP_SLTI:
			ext_rv_wr(regs, d, ((i64)regs[in->operands[1].reg] < (i64)in->operands[2].i) ? 1 : 0);
			return true;
		case OP_SLTIU:
			ext_rv_wr(regs, d, (regs[in->operands[1].reg] < (u64)in->operands[2].i) ? 1 : 0);
			return true;
		case OP_XORI: ext_rv_wr(regs, d, regs[in->operands[1].reg] ^ in->operands[2].i); return true;
		case OP_ORI: ext_rv_wr(regs, d, regs[in->operands[1].reg] | in->operands[2].i); return true;
		case OP_ANDI: ext_rv_wr(regs, d, regs[in->operands[1].reg] & in->operands[2].i); return true;
		case OP_SLLI:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] << (in->operands[2].i & 0x3F));
			return true;
		case OP_SRLI:
			ext_rv_wr(regs, d, regs[in->operands[1].reg] >> (in->operands[2].i & 0x3F));
			return true;
		case OP_SRAI:
			ext_rv_wr(regs, d, (u64)((i64)regs[in->operands[1].reg] >> (in->operands[2].i & 0x3F)));
			return true;
		case OP_LUI: ext_rv_wr(regs, d, (u64)(i64)(i32)((u32)in->operands[1].i << 12)); return true;
	}

	return false;
}

#endif // #ifndef EXT_RV32I_RUN_CUH
