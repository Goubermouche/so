#ifndef EXT_RV32M_RUN_CUH
#define EXT_RV32M_RUN_CUH

#include "ext/rv32i/run.cuh"
#include "int/instruction.cuh"

SO_HD bool ext_rv32m_run(u32 op, u64 regs[32], const int_inst* in) {
	const u32 d = (u32)in->operands[0].reg;
	const u64 a = regs[in->operands[1].reg];
	const u64 b = regs[in->operands[2].reg];

	switch(op) {
		case OP_MUL: ext_rv_wr(regs, d, a * b); return true;
		case OP_MULH: {
			const __int128 sa = (__int128)(i64)a;
			const __int128 sb = (__int128)(i64)b;
			ext_rv_wr(regs, d, (u64)(i64)((sa * sb) >> 64));
			return true;
		}
		case OP_MULHSU: {
			const __int128 sa = (__int128)(i64)a;
			const __int128 ub = (__int128)(unsigned __int128)b;
			ext_rv_wr(regs, d, (u64)(i64)((sa * ub) >> 64));
			return true;
		}
		case OP_MULHU: {
			const unsigned __int128 ua = (unsigned __int128)a;
			const unsigned __int128 ub = (unsigned __int128)b;
			ext_rv_wr(regs, d, (u64)((ua * ub) >> 64));
			return true;
		}
		case OP_DIV: {
			const i64 sa = (i64)a;
			const i64 sb = (i64)b;
			i64 q;

			if(sb == 0) {
				q = -1;
			} else if(sa == (i64)0x8000000000000000ULL && sb == -1) {
				q = sa;
			} else {
				q = sa / sb;
			}

			ext_rv_wr(regs, d, (u64)q);
			return true;
		}
		case OP_DIVU: {
			ext_rv_wr(regs, d, b == 0 ? (u64)-1 : a / b);
			return true;
		}
		case OP_REM: {
			const i64 sa = (i64)a;
			const i64 sb = (i64)b;
			i64 r;

			if(sb == 0) {
				r = sa;
			} else if(sa == (i64)0x8000000000000000ULL && sb == -1) {
				r = 0;
			} else {
				r = sa % sb;
			}

			ext_rv_wr(regs, d, (u64)r);
			return true;
		}
		case OP_REMU: {
			ext_rv_wr(regs, d, b == 0 ? a : a % b);
			return true;
		}
	}

	return false;
}

#endif // #ifndef EXT_RV32M_RUN_CUH
