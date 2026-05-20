#ifndef SMT_SMT_H
#define SMT_SMT_H

#include "cpu/instruction.cuh"
#include "cpu/program.h"
#include <vector>
#include <z3++.h>

// register accesses
#define A (s.r[d.s1])
#define B (s.r[d.s2])

// write and return tail
#define WR(expr)                                                               \
	do {                                                                         \
		smt::wr(ctx, s, d.d, (expr));                                              \
		return true;                                                               \
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
#define OVF_SIGNED(a, b, imin, ones)                                           \
	AND2(EQUIVALENT((a), (imin)), EQUIVALENT((b), (ones)))

namespace sup::smt {
static constexpr u32 TIMEOUT_MS = 10000;

struct decode {
	u32 op;
	u32 d;
	u32 s1;
	u32 s2;
	z3::expr imm;
};

struct state {
	std::vector<z3::expr> r;
	state(z3::context& ctx) : r(32, ctx.bv_val(0, 64)) {}
};

struct result {
	enum kind {
		EQUIVALENT,
		COUNTEREXAMPLE,
		TIMEOUT,
		ERROR,
	};

	kind kind;
	cpu_state counterexample;
};

result equiv(const program& a, const program& b, u64 live_outs);

z3::expr low6(z3::context& ctx, const z3::expr& v);
z3::expr sext_w(z3::context& ctx, const z3::expr& v64);
z3::expr bv32(z3::context& ctx, u64 v);
z3::expr bv64(z3::context& ctx, u64 v);
z3::expr ite_bool_to_bv64(z3::context& ctx, const z3::expr& cond);

void wr(z3::context& ctx, state& state, u32 d, const z3::expr& v);
void pin_x0(z3::context& ctx, state& state);
state make_input_state(z3::context& ctx);
state run(z3::context& ctx, const state& in, const program& p);
} // namespace sup::smt

#endif // #ifndef SMT_SMT_H
