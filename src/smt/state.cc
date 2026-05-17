#include "smt/state.h"

Z3_ast smt_low6(Z3_context ctx, Z3_ast v) {
	Z3_sort s64 = Z3_mk_bv_sort(ctx, 64);
	Z3_ast mask = Z3_mk_unsigned_int64(ctx, 0x3F, s64);
	return Z3_mk_bvand(ctx, v, mask);
}

Z3_ast smt_sext_w(Z3_context ctx, Z3_ast v64) {
	Z3_ast lo32 = Z3_mk_extract(ctx, 31, 0, v64);
	return Z3_mk_sign_ext(ctx, 32, lo32);
}

Z3_ast smt_bv32(Z3_context ctx, u64 v) {
	Z3_sort s32 = Z3_mk_bv_sort(ctx, 32);
	return Z3_mk_unsigned_int64(ctx, v, s32);
}

Z3_ast smt_bv64(Z3_context ctx, u64 v) {
	Z3_sort s64 = Z3_mk_bv_sort(ctx, 64);
	return Z3_mk_unsigned_int64(ctx, v, s64);
}

Z3_ast smt_ite_bool_to_bv64(Z3_context ctx, Z3_ast cond) {
	return Z3_mk_ite(ctx, cond, smt_bv64(ctx, 1), smt_bv64(ctx, 0));
}

void smt_wr(Z3_context ctx, smt_state* state, u32 d, Z3_ast v) {
	if(d == 0) { return; }
	Z3_inc_ref(ctx, v);
	if(state->r[d]) { Z3_dec_ref(ctx, state->r[d]); }
	state->r[d] = v;
}

void smt_pin_x0(Z3_context ctx, smt_state* state) {
	// pin x0 = 0; replaces whatever's currently in slot 0, managing refs
	Z3_sort s64 = Z3_mk_bv_sort(ctx, 64);
	Z3_ast zero = Z3_mk_unsigned_int64(ctx, 0, s64);
	Z3_inc_ref(ctx, zero);
	if(state->r[0]) Z3_dec_ref(ctx, state->r[0]);
	state->r[0] = zero;
}

Z3_ast smt_mk_bv64_const(Z3_context ctx, const c8* name) {
	Z3_sort s64 = Z3_mk_bv_sort(ctx, 64);
	Z3_symbol sym = Z3_mk_string_symbol(ctx, name);
	Z3_ast c = Z3_mk_const(ctx, sym, s64);
	Z3_inc_ref(ctx, c);
	return c;
}

void smt_free_state(Z3_context ctx, smt_state* state) {
	for(u32 i = 0; i < 32; ++i) {
		if(state->r[i]) {
			Z3_dec_ref(ctx, state->r[i]);
			state->r[i] = 0;
		}
	}
}

smt_state smt_clone_state(Z3_context ctx, const smt_state* src) {
	smt_state out = {};
	for(u32 i = 0; i < 32; ++i) {
		out.r[i] = src->r[i];
		if(out.r[i]) Z3_inc_ref(ctx, out.r[i]);
	}
	return out;
}

smt_state smt_make_input_state(Z3_context ctx) {
	static const c8* names[32] = {
		"s_x0",	 "s_x1",	"s_x2",	 "s_x3",	"s_x4",	 "s_x5",	"s_x6",	 "s_x7",
		"s_x8",	 "s_x9",	"s_x10", "s_x11", "s_x12", "s_x13", "s_x14", "s_x15",
		"s_x16", "s_x17", "s_x18", "s_x19", "s_x20", "s_x21", "s_x22", "s_x23",
		"s_x24", "s_x25", "s_x26", "s_x27", "s_x28", "s_x29", "s_x30", "s_x31",
	};
	smt_state a = {};
	for(u32 i = 0; i < 32; ++i) { a.r[i] = smt_mk_bv64_const(ctx, names[i]); }
	return a;
}
