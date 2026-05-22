#ifndef EXT_RV64M_RUN_CUH
#define EXT_RV64M_RUN_CUH

#include "cpu/instruction.cuh"
#include "extensions/rv32i/run.cuh"

HostDevice B32 ext_rv64m_run(U32 op, U64 regs[32], const Instruction* in) {
	const U32 d = (U32)in->operands[0].reg;
	const U64 a = regs[in->operands[1].reg];
	const U64 b = regs[in->operands[2].reg];

	switch(op) {
		case InstructionOpcode_Mulw: {
			const I32 r = (I32)a * (I32)b;
			ext_rv_wr(regs, d, (U64)(I64)r);
			return true;
		}
		case InstructionOpcode_Divw: {
			const I32 sa = (I32)a;
			const I32 sb = (I32)b;
			I32 r;

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
			const U32 ua = (U32)a;
			const U32 ub = (U32)b;
			ext_rv_wr(regs, d, (U64)ext_rv_sext32(ub == 0 ? (U32)-1 : ua / ub));
			return true;
		}
		case InstructionOpcode_Remw: {
			const I32 sa = (I32)a;
			const I32 sb = (I32)b;
			I32 r;

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
			const U32 ua = (U32)a;
			const U32 ub = (U32)b;
			ext_rv_wr(regs, d, (U64)ext_rv_sext32(ub == 0 ? ua : ua % ub));
			return true;
		}
	}

	return false;
}

#endif // #ifndef EXT_RV64M_RUN_CUH
