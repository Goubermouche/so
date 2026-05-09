#ifndef EXT_RV32M_SMT_CUH
#define EXT_RV32M_SMT_CUH

#include "smt/smt_state.h"

inline bool ext_rv32m_smt(Z3_context ctx, smt_state* s, u32 op, u32 d, u32 s1, u32 s2,
													Z3_ast /*imm*/) {
	switch(op) {
	case OP_MUL: smt_wr(ctx, s, d, Z3_mk_bvmul(ctx, s->r[s1], s->r[s2])); return true;
	case OP_MULH: {
		Z3_ast a = Z3_mk_sign_ext(ctx, 64, s->r[s1]);
		Z3_ast b = Z3_mk_sign_ext(ctx, 64, s->r[s2]);
		Z3_ast m = Z3_mk_bvmul(ctx, a, b);
		smt_wr(ctx, s, d, Z3_mk_extract(ctx, 127, 64, m));
		return true;
	}
	case OP_MULHSU: {
		Z3_ast a = Z3_mk_sign_ext(ctx, 64, s->r[s1]);
		Z3_ast b = Z3_mk_zero_ext(ctx, 64, s->r[s2]);
		Z3_ast m = Z3_mk_bvmul(ctx, a, b);
		smt_wr(ctx, s, d, Z3_mk_extract(ctx, 127, 64, m));
		return true;
	}
	case OP_MULHU: {
		Z3_ast a = Z3_mk_zero_ext(ctx, 64, s->r[s1]);
		Z3_ast b = Z3_mk_zero_ext(ctx, 64, s->r[s2]);
		Z3_ast m = Z3_mk_bvmul(ctx, a, b);
		smt_wr(ctx, s, d, Z3_mk_extract(ctx, 127, 64, m));
		return true;
	}
	case OP_DIV: {
		Z3_ast a = s->r[s1];
		Z3_ast b = s->r[s2];
		Z3_ast zero = smt_bv64(ctx, 0);
		Z3_ast minus_one = smt_bv64(ctx, (u64)-1);
		Z3_ast int_min = smt_bv64(ctx, 0x8000000000000000ULL);
		Z3_ast is_zero = Z3_mk_eq(ctx, b, zero);
		Z3_ast eq_min = Z3_mk_eq(ctx, a, int_min);
		Z3_ast eq_m1 = Z3_mk_eq(ctx, b, minus_one);
		Z3_ast ovf_args[2] = {eq_min, eq_m1};
		Z3_ast is_ovf = Z3_mk_and(ctx, 2, ovf_args);
		Z3_ast inner = Z3_mk_ite(ctx, is_ovf, a, Z3_mk_bvsdiv(ctx, a, b));
		Z3_ast q = Z3_mk_ite(ctx, is_zero, minus_one, inner);
		smt_wr(ctx, s, d, q);
		return true;
	}
	case OP_DIVU: {
		Z3_ast a = s->r[s1];
		Z3_ast b = s->r[s2];
		Z3_ast is_zero = Z3_mk_eq(ctx, b, smt_bv64(ctx, 0));
		smt_wr(ctx, s, d, Z3_mk_ite(ctx, is_zero, smt_bv64(ctx, (u64)-1), Z3_mk_bvudiv(ctx, a, b)));
		return true;
	}
	case OP_REM: {
		Z3_ast a = s->r[s1];
		Z3_ast b = s->r[s2];
		Z3_ast zero = smt_bv64(ctx, 0);
		Z3_ast minus_one = smt_bv64(ctx, (u64)-1);
		Z3_ast int_min = smt_bv64(ctx, 0x8000000000000000ULL);
		Z3_ast is_zero = Z3_mk_eq(ctx, b, zero);
		Z3_ast eq_min = Z3_mk_eq(ctx, a, int_min);
		Z3_ast eq_m1 = Z3_mk_eq(ctx, b, minus_one);
		Z3_ast ovf_args[2] = {eq_min, eq_m1};
		Z3_ast is_ovf = Z3_mk_and(ctx, 2, ovf_args);
		Z3_ast inner = Z3_mk_ite(ctx, is_ovf, zero, Z3_mk_bvsrem(ctx, a, b));
		Z3_ast q = Z3_mk_ite(ctx, is_zero, a, inner);
		smt_wr(ctx, s, d, q);
		return true;
	}
	case OP_REMU: {
		Z3_ast a = s->r[s1];
		Z3_ast b = s->r[s2];
		Z3_ast is_zero = Z3_mk_eq(ctx, b, smt_bv64(ctx, 0));
		smt_wr(ctx, s, d, Z3_mk_ite(ctx, is_zero, a, Z3_mk_bvurem(ctx, a, b)));
		return true;
	}
	}
	return false;
}

#endif // #ifndef EXT_RV32M_SMT_CUH
