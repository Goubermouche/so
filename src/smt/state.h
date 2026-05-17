#ifndef SMT_STATE_H
#define SMT_STATE_H

#include "cpu/instruction.cuh"
#include <z3.h>

// register accesses
#define A (s->r[s1])
#define B (s->r[s2])

// write and return tail
#define WR(expr)                                                               \
	do {                                                                         \
		smt_wr(ctx, s, d, (expr));                                                 \
		return true;                                                               \
	} while(0)

// z3 wrappers
#define EQ(x, y) Z3_mk_eq(ctx, (x), (y))
#define ITE(c, t, e) Z3_mk_ite(ctx, (c), (t), (e))
#define EXTRACT(hi, lo, x) Z3_mk_extract(ctx, (hi), (lo), (x))
#define SEXT(n, x) Z3_mk_sign_ext(ctx, (n), (x))
#define ZEXT(n, x) Z3_mk_zero_ext(ctx, (n), (x))
#define AND2(x, y) Z3_mk_and(ctx, 2, (Z3_ast[2]){(x), (y)})
#define LO32(x) EXTRACT(31, 0, (x))
#define SH5_32(x) ZEXT(27, EXTRACT(4, 0, (x)))

// signed-overflow guard
#define OVF_SIGNED(a, b, imin, ones) AND2(EQ((a), (imin)), EQ((b), (ones)))

typedef struct smt_state {
	Z3_ast r[32];
} smt_state;

Z3_ast smt_low6(Z3_context ctx, Z3_ast v);
Z3_ast smt_sext_w(Z3_context ctx, Z3_ast v64);
Z3_ast smt_bv32(Z3_context ctx, u64 v);
Z3_ast smt_bv64(Z3_context ctx, u64 v);
Z3_ast smt_ite_bool_to_bv64(Z3_context ctx, Z3_ast cond);
Z3_ast smt_mk_bv64_const(Z3_context ctx, const c8* name);

void smt_wr(Z3_context ctx, smt_state* state, u32 d, Z3_ast v);
void smt_pin_x0(Z3_context ctx, smt_state* state);

smt_state smt_make_input_state(Z3_context ctx);
smt_state smt_clone_state(Z3_context ctx, const smt_state* src);
void smt_free_state(Z3_context ctx, smt_state* state);

#endif // ifndef SMT_STATE_H
