#ifndef EXT_RV64M_SMT_CUH
#define EXT_RV64M_SMT_CUH

#include "smt/state.h"

inline bool ext_rv64m_smt(Z3_context ctx, smt_state* s, u32 op, u32 d, u32 s1, u32 s2, Z3_ast imm) {
	switch(op) {
		case OP_MULW: WR(SEXT(32, Z3_mk_bvmul(ctx, LO32(A), LO32(B))));
		case OP_DIVW: {
			Z3_ast a = LO32(A);
			Z3_ast b = LO32(B);
			Z3_ast zero = smt_bv32(ctx, 0);
			Z3_ast all_ones = smt_bv32(ctx, 0xFFFFFFFF);
			Z3_ast int_min = smt_bv32(ctx, 0x80000000);
			Z3_ast is_zero = EQ(b, zero);
			Z3_ast is_ovf = OVF_SIGNED(a, b, int_min, all_ones);
			Z3_ast inner = ITE(is_ovf, a, Z3_mk_bvsdiv(ctx, a, b));
			WR(SEXT(32, ITE(is_zero, all_ones, inner)));
		}
		case OP_DIVUW: {
			Z3_ast a = LO32(A);
			Z3_ast b = LO32(B);
			Z3_ast is_zero = EQ(b, smt_bv32(ctx, 0));
			WR(SEXT(32, ITE(is_zero, smt_bv32(ctx, 0xFFFFFFFF), Z3_mk_bvudiv(ctx, a, b))));
		}
		case OP_REMW: {
			Z3_ast a = LO32(A);
			Z3_ast b = LO32(B);
			Z3_ast zero = smt_bv32(ctx, 0);
			Z3_ast all_ones = smt_bv32(ctx, 0xFFFFFFFF);
			Z3_ast int_min = smt_bv32(ctx, 0x80000000);
			Z3_ast is_zero = EQ(b, zero);
			Z3_ast is_ovf = OVF_SIGNED(a, b, int_min, all_ones);
			Z3_ast inner = ITE(is_ovf, zero, Z3_mk_bvsrem(ctx, a, b));
			WR(SEXT(32, ITE(is_zero, a, inner)));
		}
		case OP_REMUW: {
			Z3_ast a = LO32(A);
			Z3_ast b = LO32(B);
			Z3_ast is_zero = EQ(b, smt_bv32(ctx, 0));
			WR(SEXT(32, ITE(is_zero, a, Z3_mk_bvurem(ctx, a, b))));
		}
	}
	return false;
}

#endif // EXT_RV64M_SMT_CUH
