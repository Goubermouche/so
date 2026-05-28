#ifndef EXT_RV32M_RUN_CUH
#define EXT_RV32M_RUN_CUH

#include "cpu/instruction.cuh"
#include "extensions/rv32i/run.cuh"

HostDevice B32 ext_rv32m_run(U32 op, U64 regs[32], Instruction* in) {
	U32 d = (U32)in->operands[0].reg;
	U64 a = regs[in->operands[1].reg];
	U64 b = regs[in->operands[2].reg];

	switch(op) {
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
			I64 sa = (I64)a;
			I64 sb = (I64)b;
			I64 q;

			if(sb == 0) {
				q = -1;
			} else if(sa == (I64)0x8000000000000000ULL && sb == -1) {
				q = sa;
			} else {
				q = sa / sb;
			}

			ext_rv_wr(regs, d, (U64)q);
			return true;
		}
		case InstructionOpcode_Divu: {
			ext_rv_wr(regs, d, b == 0 ? (U64)-1 : a / b);
			return true;
		}
		case InstructionOpcode_Rem: {
			I64 sa = (I64)a;
			I64 sb = (I64)b;
			I64 r;

			if(sb == 0) {
				r = sa;
			} else if(sa == (I64)0x8000000000000000ULL && sb == -1) {
				r = 0;
			} else {
				r = sa % sb;
			}

			ext_rv_wr(regs, d, (U64)r);
			return true;
		}
		case InstructionOpcode_Remu: {
			ext_rv_wr(regs, d, b == 0 ? a : a % b);
			return true;
		}
	}

	return false;
}

#endif // #ifndef EXT_RV32M_RUN_CUH
