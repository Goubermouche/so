#ifndef EXT_RV64M_SMT_CUH
#define EXT_RV64M_SMT_CUH

#include "smt/smt_state.h"

inline Z3_ast ext_bv32(Z3_context ctx, u64 v) {
	Z3_sort s32 = Z3_mk_bv_sort(ctx, 32);
	return Z3_mk_unsigned_int64(ctx, v, s32);
}

inline bool ext_rv64m_smt(Z3_context ctx, smt_state& regs, u32 op, u32 d, u32 s1, u32 s2,
													Z3_ast /*imm*/) {
	switch(op) {
	case OP_MULW: {
		Z3_ast a = Z3_mk_extract(ctx, 31, 0, regs[s1]);
		Z3_ast b = Z3_mk_extract(ctx, 31, 0, regs[s2]);
		smt_wr(ctx, regs, d, Z3_mk_sign_ext(ctx, 32, Z3_mk_bvmul(ctx, a, b)));
		return true;
	}
	case OP_DIVW: {
		Z3_ast a = Z3_mk_extract(ctx, 31, 0, regs[s1]);
		Z3_ast b = Z3_mk_extract(ctx, 31, 0, regs[s2]);
		Z3_ast zero = ext_bv32(ctx, 0);
		Z3_ast all_ones = ext_bv32(ctx, 0xFFFFFFFF);
		Z3_ast int_min = ext_bv32(ctx, 0x80000000);
		Z3_ast is_zero = Z3_mk_eq(ctx, b, zero);
		Z3_ast eq_min = Z3_mk_eq(ctx, a, int_min);
		Z3_ast eq_m1 = Z3_mk_eq(ctx, b, all_ones);
		Z3_ast ovf_args[2] = {eq_min, eq_m1};
		Z3_ast is_ovf = Z3_mk_and(ctx, 2, ovf_args);
		Z3_ast inner = Z3_mk_ite(ctx, is_ovf, a, Z3_mk_bvsdiv(ctx, a, b));
		Z3_ast res = Z3_mk_ite(ctx, is_zero, all_ones, inner);
		smt_wr(ctx, regs, d, Z3_mk_sign_ext(ctx, 32, res));
		return true;
	}
	case OP_DIVUW: {
		Z3_ast a = Z3_mk_extract(ctx, 31, 0, regs[s1]);
		Z3_ast b = Z3_mk_extract(ctx, 31, 0, regs[s2]);
		Z3_ast is_zero = Z3_mk_eq(ctx, b, ext_bv32(ctx, 0));
		Z3_ast res = Z3_mk_ite(ctx, is_zero, ext_bv32(ctx, 0xFFFFFFFF), Z3_mk_bvudiv(ctx, a, b));
		smt_wr(ctx, regs, d, Z3_mk_sign_ext(ctx, 32, res));
		return true;
	}
	case OP_REMW: {
		Z3_ast a = Z3_mk_extract(ctx, 31, 0, regs[s1]);
		Z3_ast b = Z3_mk_extract(ctx, 31, 0, regs[s2]);
		Z3_ast zero = ext_bv32(ctx, 0);
		Z3_ast all_ones = ext_bv32(ctx, 0xFFFFFFFF);
		Z3_ast int_min = ext_bv32(ctx, 0x80000000);
		Z3_ast is_zero = Z3_mk_eq(ctx, b, zero);
		Z3_ast eq_min = Z3_mk_eq(ctx, a, int_min);
		Z3_ast eq_m1 = Z3_mk_eq(ctx, b, all_ones);
		Z3_ast ovf_args[2] = {eq_min, eq_m1};
		Z3_ast is_ovf = Z3_mk_and(ctx, 2, ovf_args);
		Z3_ast inner = Z3_mk_ite(ctx, is_ovf, zero, Z3_mk_bvsrem(ctx, a, b));
		Z3_ast res = Z3_mk_ite(ctx, is_zero, a, inner);
		smt_wr(ctx, regs, d, Z3_mk_sign_ext(ctx, 32, res));
		return true;
	}
	case OP_REMUW: {
		Z3_ast a = Z3_mk_extract(ctx, 31, 0, regs[s1]);
		Z3_ast b = Z3_mk_extract(ctx, 31, 0, regs[s2]);
		Z3_ast is_zero = Z3_mk_eq(ctx, b, ext_bv32(ctx, 0));
		Z3_ast res = Z3_mk_ite(ctx, is_zero, a, Z3_mk_bvurem(ctx, a, b));
		smt_wr(ctx, regs, d, Z3_mk_sign_ext(ctx, 32, res));
		return true;
	}
	}
	return false;
}

#endif // #ifndef EXT_RV64M_SMT_CUH
