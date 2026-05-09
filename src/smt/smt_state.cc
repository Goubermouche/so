#include "smt/smt_state.h"

Z3_ast smt_low6(Z3_context ctx, Z3_ast v) {
	Z3_sort s64 = Z3_mk_bv_sort(ctx, 64);
	Z3_ast mask = Z3_mk_unsigned_int64(ctx, 0x3F, s64);
	return Z3_mk_bvand(ctx, v, mask);
}

Z3_ast smt_sext_w(Z3_context ctx, Z3_ast v64) {
	Z3_ast lo32 = Z3_mk_extract(ctx, 31, 0, v64);
	return Z3_mk_sign_ext(ctx, 32, lo32);
}

Z3_ast smt_bv64(Z3_context ctx, u64 v) {
	Z3_sort s64 = Z3_mk_bv_sort(ctx, 64);
	return Z3_mk_unsigned_int64(ctx, v, s64);
}

Z3_ast smt_ite_bool_to_bv64(Z3_context ctx, Z3_ast cond) {
	return Z3_mk_ite(ctx, cond, smt_bv64(ctx, 1), smt_bv64(ctx, 0));
}

void smt_wr(Z3_context ctx, smt_state& regs, u32 d, Z3_ast v) {
	if(d == 0) { return; }
	Z3_inc_ref(ctx, v);
	if(regs[d]) { Z3_dec_ref(ctx, regs[d]); }
	regs[d] = v;
}

void smt_free_state(Z3_context ctx, smt_state& regs) {
	for(u32 i = 0; i < 32; ++i) {
		if(regs[i]) {
			Z3_dec_ref(ctx, regs[i]);
			regs[i] = nullptr;
		}
	}
}
