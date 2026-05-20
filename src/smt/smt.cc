#include "smt/smt.h"
#include "extensions/rv32i/smt.h"
#include "extensions/rv32m/smt.h"
#include "extensions/rv64i/smt.h"
#include "extensions/rv64m/smt.h"
#include "util/type.h"
#include <z3++.h>

namespace sup::smt {
result equiv(const program& a, const program& b, u64 live_outs) {
	const f64 t0 = get_time_ms();
	result r = {};

	try {
		// init Z3
		z3::context ctx;
		z3::params params(ctx);
		params.set("timeout", TIMEOUT_MS);

		// make input state
		state in = make_input_state(ctx);
		pin_x0(ctx, in);

		// run programs
		state out_target = run(ctx, in, a);
		state out_rewrite = run(ctx, in, b);

		// OR over live regs of (out_target[reg] != out_rewrite[reg])
		z3::expr_vector disjuncts(ctx);
		for(u32 reg = 0; reg < 32; ++reg) {
			if(reg == 0) continue;
			if(live_outs & (1ULL << reg)) {
				disjuncts.push_back(out_target.r[reg] != out_rewrite.r[reg]);
			}
		}

		if(disjuncts.empty()) {
			// trivially equivalent
			r.kind = result::EQUIVALENT;
			return r;
		}

		z3::expr formula = z3::mk_or(disjuncts);

		// solve
		z3::solver solver(ctx);
		solver.set(params);
		solver.add(formula);

		z3::check_result chk = solver.check();

		switch(chk) {
			case z3::unsat: r.kind = result::EQUIVALENT; break;
			case z3::sat: {
				// programs are not equivalent => build counterexample
				z3::model m = solver.get_model();
				for(u32 i = 0; i < 32; ++i) {
					if(i == 0) {
						r.counterexample.regs[i] = 0;
						continue;
					}
					z3::expr v = m.eval(in.r[i], true);
					uint64_t raw = 0;
					// Fall back slightly to C API for extraction safety across Z3
					// versions
					if(Z3_get_numeral_uint64(ctx, v, &raw)) {
						r.counterexample.regs[i] = raw;
					} else {
						r.counterexample.regs[i] = 0;
					}
				}
				r.kind = result::COUNTEREXAMPLE;
				break;
			}
			case z3::unknown:
			default: r.kind = result::TIMEOUT; break;
		}
	} catch(z3::exception& e) {
		fprintf(stderr, "error: smt::z3: %s\n", e.msg());
		r.kind = result::ERROR;
	}

	return r;
}

z3::expr low6(z3::context& ctx, const z3::expr& v) {
	return v & ctx.bv_val(0x3F, 64);
}

z3::expr sext_w(z3::context& ctx, const z3::expr& v64) {
	z3::expr lo32 = v64.extract(31, 0);
	return z3::sext(lo32, 32);
}

z3::expr bv32(z3::context& ctx, u64 v) { return ctx.bv_val((uint64_t)v, 32); }

z3::expr bv64(z3::context& ctx, u64 v) { return ctx.bv_val((uint64_t)v, 64); }

z3::expr ite_bool_to_bv64(z3::context& ctx, const z3::expr& cond) {
	return z3::ite(cond, ctx.bv_val(1, 64), ctx.bv_val(0, 64));
}

void wr(z3::context& ctx, state& state, u32 d, const z3::expr& v) {
	if(d == 0) { return; }
	state.r[d] = v;
}

void pin_x0(z3::context& ctx, state& state) { state.r[0] = ctx.bv_val(0, 64); }

state make_input_state(z3::context& ctx) {
	static const c8* names[32] = {
		"s_x0",	 "s_x1",	"s_x2",	 "s_x3",	"s_x4",	 "s_x5",	"s_x6",	 "s_x7",
		"s_x8",	 "s_x9",	"s_x10", "s_x11", "s_x12", "s_x13", "s_x14", "s_x15",
		"s_x16", "s_x17", "s_x18", "s_x19", "s_x20", "s_x21", "s_x22", "s_x23",
		"s_x24", "s_x25", "s_x26", "s_x27", "s_x28", "s_x29", "s_x30", "s_x31",
	};

	// Call the new constructor with the z3::context
	state a(ctx);

	for(u32 i = 0; i < 32; ++i) { a.r[i] = ctx.bv_const(names[i], 64); }
	return a;
}

state run(z3::context& ctx, const state& in, const program& p) {
	state regs = in;
	pin_x0(ctx, regs);

	for(u32 i = 0; i < p.size; ++i) {
		const inst& ins = p[i];
		const u32 op = (u32)ins.op;

		if(op == OP_NOP) { continue; }

		// get operands
		const inst_spec* spec = &INST_DB_HOST.row[op];
		z3::expr imm = ctx.bv_val(0, 64);

		// init operands
		for(u32 k = 0; k < 4; ++k) {
			if(spec->operands[k] == OPERAND_IMM) {
				imm = ctx.bv_val((uint64_t)ins.operands[k].i, 64);
				break;
			}
		}

		decode dec = {.imm = imm};
		dec.op = op;
		dec.d = spec->dst_slot >= 0 ? ins.operands[spec->dst_slot].reg : 0;
		dec.s1 = spec->src_slot >= 0 ? ins.operands[spec->src_slot].reg : 0;
		dec.s2 = spec->src2_slot >= 0 ? ins.operands[spec->src2_slot].reg : 0;

		// build solver
		b32 handled = false;
		if(!handled) handled = ext_rv32i_smt(ctx, regs, dec);
		if(!handled) handled = ext_rv64i_smt(ctx, regs, dec);
		if(!handled) handled = ext_rv32m_smt(ctx, regs, dec);
		if(!handled) handled = ext_rv64m_smt(ctx, regs, dec);

		ASSERT(handled, "smt: unknown opcode\n");
		pin_x0(ctx, regs);
	}

	return regs;
}
} // namespace sup::smt