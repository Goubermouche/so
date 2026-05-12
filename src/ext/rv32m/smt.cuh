#ifndef EXT_RV32M_SMT_CUH
#define EXT_RV32M_SMT_CUH

#include "smt/state.h"

inline bool ext_rv32m_smt(Z3_context ctx, smt_state* s, u32 op, u32 d, u32 s1, u32 s2, Z3_ast imm) {
	switch(op) {
		case OP_MUL:    WR(Z3_mk_bvmul(ctx, A, B));
		case OP_MULH:   WR(EXTRACT(127, 64, Z3_mk_bvmul(ctx, SEXT(64, A), SEXT(64, B))));
		case OP_MULHSU: WR(EXTRACT(127, 64, Z3_mk_bvmul(ctx, SEXT(64, A), ZEXT(64, B))));
		case OP_MULHU:  WR(EXTRACT(127, 64, Z3_mk_bvmul(ctx, ZEXT(64, A), ZEXT(64, B))));
		case OP_DIV: {
			Z3_ast minus_one = smt_bv64(ctx, (u64)-1);
			Z3_ast int_min = smt_bv64(ctx, 0x8000000000000000ULL);
			Z3_ast is_zero = EQ(B, smt_bv64(ctx, 0));
			Z3_ast is_ovf = OVF_SIGNED(A, B, int_min, minus_one);
			Z3_ast inner = ITE(is_ovf, A, Z3_mk_bvsdiv(ctx, A, B));
			WR(ITE(is_zero, minus_one, inner));
		}
		case OP_DIVU: {
			Z3_ast is_zero = EQ(B, smt_bv64(ctx, 0));
			WR(ITE(is_zero, smt_bv64(ctx, (u64)-1), Z3_mk_bvudiv(ctx, A, B)));
		}
		case OP_REM: {
			Z3_ast zero = smt_bv64(ctx, 0);
			Z3_ast minus_one = smt_bv64(ctx, (u64)-1);
			Z3_ast int_min = smt_bv64(ctx, 0x8000000000000000ULL);
			Z3_ast is_zero = EQ(B, zero);
			Z3_ast is_ovf = OVF_SIGNED(A, B, int_min, minus_one);
			Z3_ast inner = ITE(is_ovf, zero, Z3_mk_bvsrem(ctx, A, B));
			WR(ITE(is_zero, A, inner));
		}
		case OP_REMU: {
			Z3_ast is_zero = EQ(B, smt_bv64(ctx, 0));
			WR(ITE(is_zero, A, Z3_mk_bvurem(ctx, A, B)));
		}
	}
	return false;
}

#endif // EXT_RV32M_SMT_CUH
