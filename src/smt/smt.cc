#include "smt/smt.h"
#include "ext/rv32i/smt.cuh"
#include "ext/rv32m/smt.cuh"
#include "ext/rv64i/smt.cuh"
#include "ext/rv64m/smt.cuh"
#include "int/instruction.cuh"
#include <chrono>
#include <cstdio>
#include <cstring>
#include <z3.h>

static Z3_ast mk_bv64_const(Z3_context ctx, const char* name) {
	Z3_sort s64 = Z3_mk_bv_sort(ctx, 64);
	Z3_symbol sym = Z3_mk_string_symbol(ctx, name);
	Z3_ast c = Z3_mk_const(ctx, sym, s64);
	Z3_inc_ref(ctx, c);
	return c;
}

smt_state make_input_state(Z3_context ctx) {
	static const char* names[32] = {
		"s_x0",	 "s_x1",	"s_x2",	 "s_x3",	"s_x4",	 "s_x5",	"s_x6",	 "s_x7",
		"s_x8",	 "s_x9",	"s_x10", "s_x11", "s_x12", "s_x13", "s_x14", "s_x15",
		"s_x16", "s_x17", "s_x18", "s_x19", "s_x20", "s_x21", "s_x22", "s_x23",
		"s_x24", "s_x25", "s_x26", "s_x27", "s_x28", "s_x29", "s_x30", "s_x31",
	};
	smt_state a = {};
	for(u32 i = 0; i < 32; ++i) { a[i] = mk_bv64_const(ctx, names[i]); }
	return a;
}

// pin x0 = 0; replaces whatever's currently in slot 0, managing refs
static void pin_x0(Z3_context ctx, smt_state& regs) {
	Z3_sort s64 = Z3_mk_bv_sort(ctx, 64);
	Z3_ast zero = Z3_mk_unsigned_int64(ctx, 0, s64);
	Z3_inc_ref(ctx, zero);
	if(regs[0]) Z3_dec_ref(ctx, regs[0]);
	regs[0] = zero;
}

static smt_state clone_state(Z3_context ctx, const smt_state& src) {
	smt_state out = {};
	for(u32 i = 0; i < 32; ++i) {
		out[i] = src[i];
		if(out[i]) Z3_inc_ref(ctx, out[i]);
	}
	return out;
}

smt_state symbolic_run(Z3_context ctx, const smt_state& in, const program_slice* prog,
											 const char** unsupported_opcode) {
	smt_state regs = clone_state(ctx, in);
	pin_x0(ctx, regs);
	Z3_sort s64 = Z3_mk_bv_sort(ctx, 64);

	for(u32 i = 0; i < prog->size; ++i) {
		const inst& ins = prog->instructions[i];
		const u32 op = (u32)ins.op;

		if(op == OP_NOP) { continue; }

		const inst_spec& spec = INST_DB_HOST.row[op];
		const u32 d = spec.dst_slot >= 0 ? (u32)ins.operands[spec.dst_slot].reg : 0;
		const u32 s1 = spec.src_slot >= 0 ? (u32)ins.operands[spec.src_slot].reg : 0;
		const u32 s2 = spec.src2_slot >= 0 ? (u32)ins.operands[spec.src2_slot].reg : 0;

		Z3_ast imm = Z3_mk_unsigned_int64(ctx, 0, s64);
		Z3_inc_ref(ctx, imm);

		for(u32 k = 0; k < 4; ++k) {
			if(spec.operands[k] == inst_spec::IMM) {
				Z3_ast new_imm = Z3_mk_unsigned_int64(ctx, (u64)ins.operands[k].i, s64);
				Z3_inc_ref(ctx, new_imm);
				Z3_dec_ref(ctx, imm);
				imm = new_imm;
				break;
			}
		}

		bool handled = false;
		if(!handled) handled = ext_rv32i_smt(ctx, regs, op, d, s1, s2, imm);
		if(!handled) handled = ext_rv64i_smt(ctx, regs, op, d, s1, s2, imm);
		if(!handled) handled = ext_rv32m_smt(ctx, regs, op, d, s1, s2, imm);
		if(!handled) handled = ext_rv64m_smt(ctx, regs, op, d, s1, s2, imm);

		Z3_dec_ref(ctx, imm);

		if(!handled) {
			if(unsupported_opcode) { *unsupported_opcode = "opcode not handled by any extension"; }
			break;
		}

		pin_x0(ctx, regs);
	}

	return regs;
}

// catch any error reported through the Z3 error handler.
static thread_local char g_err_buf[512];
static thread_local bool g_err_set = false;
static void z3_error_cb(Z3_context c, Z3_error_code ec) {
	Z3_string msg = Z3_get_error_msg(c, ec);
	std::snprintf(g_err_buf, sizeof(g_err_buf), "%s", msg ? msg : "z3 error");
	g_err_set = true;
}

smt_verify_report smt_eq(const program_slice* a, const program_slice* b, u64 live_outs) {
	smt_verify_report r = {};

	Z3_config cfg = Z3_mk_config();
	Z3_context ctx = Z3_mk_context_rc(cfg);
	Z3_del_config(cfg);
	Z3_set_error_handler(ctx, z3_error_cb);
	g_err_set = false;

	Z3_params params = Z3_mk_params(ctx);
	Z3_params_inc_ref(ctx, params);
	Z3_symbol timeout_sym = Z3_mk_string_symbol(ctx, "timeout");
	Z3_params_set_uint(ctx, params, timeout_sym, SMT_TIMEOUT_MS);

	smt_state in = make_input_state(ctx);
	pin_x0(ctx, in);

	const char* err = nullptr;
	smt_state out_target = symbolic_run(ctx, in, a, &err);
	if(err || g_err_set) {
		r.kind = VERIFY_ERROR;
		r.error = err ? err : g_err_buf;
		smt_free_state(ctx, in);
		smt_free_state(ctx, out_target);
		Z3_params_dec_ref(ctx, params);
		Z3_del_context(ctx);
		return r;
	}

	smt_state out_rewrite = symbolic_run(ctx, in, b, &err);
	if(err || g_err_set) {
		r.kind = VERIFY_ERROR;
		r.error = err ? err : g_err_buf;
		smt_free_state(ctx, in);
		smt_free_state(ctx, out_target);
		smt_free_state(ctx, out_rewrite);
		Z3_params_dec_ref(ctx, params);
		Z3_del_context(ctx);
		return r;
	}

	// build disjunction: OR over live regs of (out_target[reg] != out_rewrite[reg]).
	Z3_ast disjuncts[32];
	u32 n_disj = 0;
	for(u32 reg = 0; reg < 32; ++reg) {
		if(reg == 0) continue;
		if(live_outs & (1ULL << reg)) {
			Z3_ast eq = Z3_mk_eq(ctx, out_target[reg], out_rewrite[reg]);
			Z3_ast neq = Z3_mk_not(ctx, eq);
			Z3_inc_ref(ctx, neq);
			disjuncts[n_disj++] = neq;
		}
	}

	if(n_disj == 0) {
		r.kind = VERIFY_EQUIVALENT;
		r.solve_ms = 0;
		smt_free_state(ctx, in);
		smt_free_state(ctx, out_target);
		smt_free_state(ctx, out_rewrite);
		Z3_params_dec_ref(ctx, params);
		Z3_del_context(ctx);
		return r;
	}

	Z3_ast formula = Z3_mk_or(ctx, n_disj, disjuncts);
	Z3_inc_ref(ctx, formula);
	for(u32 i = 0; i < n_disj; ++i) Z3_dec_ref(ctx, disjuncts[i]);

	Z3_solver solver = Z3_mk_solver(ctx);
	Z3_solver_inc_ref(ctx, solver);
	Z3_solver_set_params(ctx, solver, params);
	Z3_solver_assert(ctx, solver, formula);

	const auto t0 = std::chrono::high_resolution_clock::now();
	Z3_lbool chk = Z3_solver_check(ctx, solver);
	const auto t1 = std::chrono::high_resolution_clock::now();
	r.solve_ms = std::chrono::duration<f64, std::milli>(t1 - t0).count();

	switch(chk) {
	case Z3_L_FALSE: r.kind = VERIFY_EQUIVALENT; break;
	case Z3_L_TRUE: {
		Z3_model m = Z3_solver_get_model(ctx, solver);
		Z3_model_inc_ref(ctx, m);
		for(u32 i = 0; i < 32; ++i) {
			Z3_ast v = nullptr;
			if(Z3_model_eval(ctx, m, in[i], true, &v) && v) {
				Z3_inc_ref(ctx, v);
				uint64_t raw = 0;
				r.counterexample.regs[i] = Z3_get_numeral_uint64(ctx, v, &raw) ? raw : 0;
				Z3_dec_ref(ctx, v);
			} else {
				r.counterexample.regs[i] = 0;
			}
		}
		r.counterexample.regs[0] = 0;
		r.kind = VERIFY_COUNTEREXAMPLE;
		Z3_model_dec_ref(ctx, m);
		break;
	}
	case Z3_L_UNDEF:
	default: r.kind = VERIFY_TIMEOUT; break;
	}

	if(g_err_set && r.kind != VERIFY_COUNTEREXAMPLE) {
		r.kind = VERIFY_ERROR;
		r.error = g_err_buf;
	}

	Z3_dec_ref(ctx, formula);
	Z3_solver_dec_ref(ctx, solver);
	smt_free_state(ctx, in);
	smt_free_state(ctx, out_target);
	smt_free_state(ctx, out_rewrite);
	Z3_params_dec_ref(ctx, params);
	Z3_del_context(ctx);
	return r;
}
