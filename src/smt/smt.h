#ifndef SMT_SMT_H
#define SMT_SMT_H

#include "cpu/program.h"
#include <z3++.h>

// register accesses
#define A (s.r[d.s1])
#define B (s.r[d.s2])

// write and return tail
#define WR(expr)                                                                                   \
	do {                                                                                             \
		smt_wr(ctx, s, d.d, (expr));                                                                   \
		return true;                                                                                   \
	} while(0)

// z3 wrappers
#define EQUIVALENT(x, y) ((x) == (y))
#define ITE(c, t, e) z3::ite((c), (t), (e))
#define EXTRACT(hi, lo, x) (x).extract((hi), (lo))
#define SEXT(n, x) z3::sext((x), (n))
#define ZEXT(n, x) z3::zext((x), (n))
#define AND2(x, y) ((x) && (y))
#define LO32(x) EXTRACT(31, 0, (x))
#define SH5_32(x) ZEXT(27, EXTRACT(4, 0, (x)))

// signed-overflow guard
#define OVF_SIGNED(a, b, imin, ones) AND2(EQUIVALENT((a), (imin)), EQUIVALENT((b), (ones)))

static constexpr u32 TIMEOUT_MS = 10000;

typedef struct SMT_Decode {
	u32 op;
	u32 d;
	u32 s1;
	u32 s2;
	z3::expr imm;
} SMT_Decode;

typedef struct SMT_State {
	std::vector<z3::expr> r;
	SMT_State(z3::context& ctx) : r(32, ctx.bv_val(0, 64)) {}
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

SMT_Result smt_equiv(const Program& a, const Program& b, u64 live_outs);

z3::expr smt_low6(z3::context& ctx, const z3::expr& v);
z3::expr smt_sext_w(z3::context& ctx, const z3::expr& v64);
z3::expr smt_bv32(z3::context& ctx, u64 v);
z3::expr smt_bv64(z3::context& ctx, u64 v);
z3::expr smt_ite_bool_to_bv64(z3::context& ctx, const z3::expr& cond);

void smt_wr(z3::context& ctx, SMT_State& state, u32 d, const z3::expr& v);
void smt_pin_x0(z3::context& ctx, SMT_State& state);
SMT_State smt_make_input_state(z3::context& ctx);
SMT_State smt_run(z3::context& ctx, const SMT_State* in, const Program* p);

#endif // #ifndef SMT_SMT_H
