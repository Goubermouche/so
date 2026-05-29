#ifndef EXT_RUN_CUH
#define EXT_RUN_CUH

#include "cpu/instruction.cuh"

// sign-extend the low 32 bits of v to 64 bits
HostDevice I64 ext_rv_sext32(U64 v) { return (I64)(I32)(U32)v; }

HostDevice void ext_rv_wr(U64 regs[32], U32 d, U64 v) {
	regs[d] = v;
	regs[0] = 0; // pin x0
}

HostDevice B32 ext_run_inst(U32 op, U64 regs[32], Instruction* in) {
	U32 d = (U32)in->operands[0].reg;
	U64 a = regs[in->operands[1].reg & 31];
	U64 b = regs[in->operands[2].reg & 31];
	U64 imm = in->operands[2].imm;

	switch(op) {
		// rv32i
		case InstructionOpcode_Add:   ext_rv_wr(regs, d, a + b); return true;
		case InstructionOpcode_Sub:   ext_rv_wr(regs, d, a - b); return true;
		case InstructionOpcode_Sll:   ext_rv_wr(regs, d, a << (b & 0x3F)); return true;
		case InstructionOpcode_Slt:   ext_rv_wr(regs, d, ((I64)a < (I64)b) ? 1 : 0); return true;
		case InstructionOpcode_Sltu:  ext_rv_wr(regs, d, (a < b) ? 1 : 0); return true;
		case InstructionOpcode_Xor:   ext_rv_wr(regs, d, a ^ b); return true;
		case InstructionOpcode_Srl:   ext_rv_wr(regs, d, a >> (b & 0x3F)); return true;
		case InstructionOpcode_Sra:   ext_rv_wr(regs, d, (U64)((I64)a >> (b & 0x3F))); return true;
		case InstructionOpcode_Or:    ext_rv_wr(regs, d, a | b); return true;
		case InstructionOpcode_And:   ext_rv_wr(regs, d, a & b); return true;
		case InstructionOpcode_Addi:  ext_rv_wr(regs, d, a + imm); return true;
		case InstructionOpcode_Slti:  ext_rv_wr(regs, d, ((I64)a < (I64)imm) ? 1 : 0); return true;
		case InstructionOpcode_Sltiu: ext_rv_wr(regs, d, (a < (U64)imm) ? 1 : 0); return true;
		case InstructionOpcode_Xori:  ext_rv_wr(regs, d, a ^ imm); return true;
		case InstructionOpcode_Ori:   ext_rv_wr(regs, d, a | imm); return true;
		case InstructionOpcode_Andi:  ext_rv_wr(regs, d, a & imm); return true;
		case InstructionOpcode_Slli:  ext_rv_wr(regs, d, a << (imm & 0x3F)); return true;
		case InstructionOpcode_Srli:  ext_rv_wr(regs, d, a >> (imm & 0x3F)); return true;
		case InstructionOpcode_Srai:  ext_rv_wr(regs, d, (U64)((I64)a >> (imm & 0x3F))); return true;
		case InstructionOpcode_Lui:
			ext_rv_wr(regs, d, (U64)(I64)(I32)((U32)in->operands[1].imm << 12));
			return true;
		// rv64i
		case InstructionOpcode_Addiw:
			ext_rv_wr(regs, d, (U64)ext_rv_sext32((U32)a + (U32)imm));
			return true;
		case InstructionOpcode_Slliw:
			ext_rv_wr(regs, d, (U64)ext_rv_sext32((U32)a << (imm & 0x1F)));
			return true;
		case InstructionOpcode_Srliw:
			ext_rv_wr(regs, d, (U64)ext_rv_sext32((U32)a >> (imm & 0x1F)));
			return true;
		case InstructionOpcode_Sraiw:
			ext_rv_wr(regs, d, (U64)((I64)((I32)a >> (imm & 0x1F))));
			return true;
		case InstructionOpcode_Addw:
			ext_rv_wr(regs, d, (U64)ext_rv_sext32((U32)a + (U32)b));
			return true;
		case InstructionOpcode_Subw:
			ext_rv_wr(regs, d, (U64)ext_rv_sext32((U32)a - (U32)b));
			return true;
		case InstructionOpcode_Sllw:
			ext_rv_wr(regs, d, (U64)ext_rv_sext32((U32)a << (b & 0x1F)));
			return true;
		case InstructionOpcode_Srlw:
			ext_rv_wr(regs, d, (U64)ext_rv_sext32((U32)a >> (b & 0x1F)));
			return true;
		case InstructionOpcode_Sraw:
			ext_rv_wr(regs, d, (U64)((I64)((I32)a >> (b & 0x1F))));
			return true;
		// rv32m
		case InstructionOpcode_Mul: ext_rv_wr(regs, d, a * b); return true;
		case InstructionOpcode_Mulh: {
			__int128 sa = (__int128)(I64)a;
			__int128 sb = (__int128)(I64)b;
			ext_rv_wr(regs, d, (U64)(I64)((sa * sb) >> 64));
			return true;
		}
		case InstructionOpcode_Mulhsu: {
			__int128 sa = (__int128)(I64)a;
			__int128 ub = (__int128)(unsigned __int128)b;
			ext_rv_wr(regs, d, (U64)(I64)((sa * ub) >> 64));
			return true;
		}
		case InstructionOpcode_Mulhu: {
			unsigned __int128 ua = (unsigned __int128)a;
			unsigned __int128 ub = (unsigned __int128)b;
			ext_rv_wr(regs, d, (U64)((ua * ub) >> 64));
			return true;
		}
		case InstructionOpcode_Div: {
			I64 sa = (I64)a, sb = (I64)b;
			U64 q;
			if(sb == 0) {
				q = (U64)-1;
			} else if(sa == (I64)0x8000000000000000ULL && sb == -1) {
				q = (U64)sa;
			} else {
				q = (U64)(sa / sb);
			}
			ext_rv_wr(regs, d, q);
			return true;
		}
		case InstructionOpcode_Divu: ext_rv_wr(regs, d, b == 0 ? (U64)-1 : a / b); return true;
		case InstructionOpcode_Rem: {
			I64 sa = (I64)a, sb = (I64)b;
			U64 r;
			if(sb == 0) {
				r = (U64)sa;
			} else if(sa == (I64)0x8000000000000000ULL && sb == -1) {
				r = 0;
			} else {
				r = (U64)(sa % sb);
			}
			ext_rv_wr(regs, d, r);
			return true;
		}
		case InstructionOpcode_Remu: ext_rv_wr(regs, d, b == 0 ? a : a % b); return true;
		// rv64m
		case InstructionOpcode_Mulw: {
			I32 r = (I32)a * (I32)b;
			ext_rv_wr(regs, d, (U64)(I64)r);
			return true;
		}
		case InstructionOpcode_Divw: {
			I32 sa = (I32)a, sb = (I32)b, r;
			if(sb == 0) {
				r = -1;
			} else if(sa == (I32)0x80000000 && sb == -1) {
				r = sa;
			} else {
				r = sa / sb;
			}
			ext_rv_wr(regs, d, (U64)(I64)r);
			return true;
		}
		case InstructionOpcode_Divuw: {
			U32 ua = (U32)a, ub = (U32)b;
			ext_rv_wr(regs, d, (U64)ext_rv_sext32(ub == 0 ? (U32)-1 : ua / ub));
			return true;
		}
		case InstructionOpcode_Remw: {
			I32 sa = (I32)a, sb = (I32)b, r;
			if(sb == 0) {
				r = sa;
			} else if(sa == (I32)0x80000000 && sb == -1) {
				r = 0;
			} else {
				r = sa % sb;
			}
			ext_rv_wr(regs, d, (U64)(I64)r);
			return true;
		}
		case InstructionOpcode_Remuw: {
			U32 ua = (U32)a, ub = (U32)b;
			ext_rv_wr(regs, d, (U64)ext_rv_sext32(ub == 0 ? ua : ua % ub));
			return true;
		}
	}

	return false;
}

HostDevice CpuState ext_run_program(Program* prog, CpuState* in) {
	CpuState out = *in;
	out.regs[0] = 0;

	for(U32 i = 0; i < prog->size; ++i) {
		Instruction* in = &prog->instructions[i];
		U32 op = (U32)in->op;

		if(op == InstructionOpcode_Nop) { continue; }
		ext_run_inst(op, out.regs, in);
	}

	return out;
}

#endif // #ifndef EXT_RUN_CUH
