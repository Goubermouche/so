#ifndef EXT_RV64M_RUN_CUH
#define EXT_RV64M_RUN_CUH

#include "extensions/rv32i/run.cuh"
#include "cpu/instruction.cuh"

namespace sup {
SO_HD b32 ext_rv64m_run(u32 op, u64 regs[32], const inst* in) {
	const u32 d = (u32)in->operands[0].reg;
	const u64 a = regs[in->operands[1].reg];
	const u64 b = regs[in->operands[2].reg];

	switch(op) {
		case OP_MULW: {
			const i32 r = (i32)a * (i32)b;
			ext_rv_wr(regs, d, (u64)(i64)r);
			return true;
		}
		case OP_DIVW: {
			const i32 sa = (i32)a;
			const i32 sb = (i32)b;
			i32 r;

			if(sb == 0) {
				r = -1;
			} else if(sa == (i32)0x80000000 && sb == -1) {
				r = sa;
			} else {
				r = sa / sb;
			}

			ext_rv_wr(regs, d, (u64)(i64)r);
			return true;
		}
		case OP_DIVUW: {
			const u32 ua = (u32)a;
			const u32 ub = (u32)b;
			ext_rv_wr(regs, d, (u64)ext_rv_sext32(ub == 0 ? (u32)-1 : ua / ub));
			return true;
		}
		case OP_REMW: {
			const i32 sa = (i32)a;
			const i32 sb = (i32)b;
			i32 r;

			if(sb == 0) {
				r = sa;
			} else if(sa == (i32)0x80000000 && sb == -1) {
				r = 0;
			} else {
				r = sa % sb;
			}

			ext_rv_wr(regs, d, (u64)(i64)r);
			return true;
		}
		case OP_REMUW: {
			const u32 ua = (u32)a;
			const u32 ub = (u32)b;
			ext_rv_wr(regs, d, (u64)ext_rv_sext32(ub == 0 ? ua : ua % ub));
			return true;
		}
	}

	return false;
}
} // namespace sup

#endif // #ifndef EXT_RV64M_RUN_CUH
