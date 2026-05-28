#ifndef SMT_SMT_H
#define SMT_SMT_H
#include "cpu/program.h"
#include <z3.h>

// register accesses
#define SMT_A (s->r[d->s1])
#define SMT_B (s->r[d->s2])

// write and return tail
#define SMT_WR(expr)                                                                               \
	do {                                                                                             \
		smt_wr(ctx, s, d->d, (expr));                                                                  \
		return true;                                                                                   \
	} while(0)

// z3 wrappers
#define SMT_Eq(x, y) Z3_mk_eq(ctx, (x), (y))
#define SMT_Ite(c, t, e) Z3_mk_ite(ctx, (c), (t), (e))
#define SMT_Extract(hi, lo, x) Z3_mk_extract(ctx, (hi), (lo), (x))
#define SMT_Sext(n, x) Z3_mk_sign_ext(ctx, (n), (x))
#define SMT_Zext(n, x) Z3_mk_zero_ext(ctx, (n), (x))
#define SMT_AND2(x, y) Z3_mk_and(ctx, 2, (Z3_ast[2]){(x), (y)})
#define SMT_LO32(x) SMT_Extract(31, 0, (x))
#define SMT_SH5_32(x) SMT_Zext(27, SMT_Extract(4, 0, (x)))

// signed-overflow guard
#define SMT_OvfSigned(a, b, imin, ones) SMT_AND2(SMT_Eq((a), (imin)), SMT_Eq((b), (ones)))

#define SMT_TimeoutMS 10000

typedef struct SMT_Decode {
	U32 op;
	U32 d;
	U32 s1;
	U32 s2;
	Z3_ast imm;
} SMT_Decode;

typedef struct SMT_State {
	Z3_ast r[32];
} SMT_State;

typedef enum SMT_ResultType {
	SMT_ResultType_EQUIVALENT,
	SMT_ResultType_COUNTEREXAMPLE,
	SMT_ResultType_TIMEOUT,
	SMT_ResultType_ERROR,
} SMT_ResultType;

typedef struct SMT_Result {
	SMT_ResultType type;
	CpuState counterexample;
} SMT_Result;

SMT_Result smt_equiv(Program* a, Program* b, U64 live_outs);

Z3_ast smt_low6(Z3_context ctx, Z3_ast v);
Z3_ast smt_sext_w(Z3_context ctx, Z3_ast v64);
Z3_ast smt_bv32(Z3_context ctx, U64 v);
Z3_ast smt_bv64(Z3_context ctx, U64 v);
Z3_ast smt_ite_bool_to_bv64(Z3_context ctx, Z3_ast cond);
Z3_ast smt_mk_bv64_const(Z3_context ctx, const C8* name);
void smt_wr(Z3_context ctx, SMT_State* state, U32 d, Z3_ast v);
void smt_pin_x0(Z3_context ctx, SMT_State* state);
SMT_State smt_make_input_state(Z3_context ctx);
SMT_State smt_clone_state(Z3_context ctx, SMT_State* src);
void smt_free_state(Z3_context ctx, SMT_State* state);
SMT_State smt_run(Z3_context ctx, SMT_State* in, Program* p);

#endif // #ifndef SMT_SMT_H