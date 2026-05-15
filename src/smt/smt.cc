#include "smt/smt.h"
#include "extensions/rv32i/smt.cuh"
#include "extensions/rv32m/smt.cuh"
#include "extensions/rv64i/smt.cuh"
#include "extensions/rv64m/smt.cuh"
#include "util/type.h"

smt_state smt_run(Z3_context ctx, const smt_state* in, const cpu_program* prog) {
	smt_state regs = smt_clone_state(ctx, in);
	smt_pin_x0(ctx, &regs);
	Z3_sort s64 = Z3_mk_bv_sort(ctx, 64);

	for(u32 i = 0; i < prog->size; ++i) {
		const cpu_inst* ins = &prog->instructions[i];
		const u32 op = (u32)ins->op;

		if(op == OP_NOP) { continue; }

		const cpu_inst_spec* spec = &CPU_INST_DB_HOST.row[op];
		const u32 d = spec->dst_slot >= 0 ? (u32)ins->operands[spec->dst_slot].reg : 0;
		const u32 s1 = spec->src_slot >= 0 ? (u32)ins->operands[spec->src_slot].reg : 0;
		const u32 s2 = spec->src2_slot >= 0 ? (u32)ins->operands[spec->src2_slot].reg : 0;

		Z3_ast imm = Z3_mk_unsigned_int64(ctx, 0, s64);
		Z3_inc_ref(ctx, imm);

		for(u32 k = 0; k < 4; ++k) {
			if(spec->operands[k] == CPU_OPERAND_IMM) {
				Z3_ast new_imm = Z3_mk_unsigned_int64(ctx, (u64)ins->operands[k].i, s64);
				Z3_inc_ref(ctx, new_imm);
				Z3_dec_ref(ctx, imm);
				imm = new_imm;
				break;
			}
		}

		bool handled = false;
		if(!handled) handled = ext_rv32i_smt(ctx, &regs, op, d, s1, s2, imm);
		if(!handled) handled = ext_rv64i_smt(ctx, &regs, op, d, s1, s2, imm);
		if(!handled) handled = ext_rv32m_smt(ctx, &regs, op, d, s1, s2, imm);
		if(!handled) handled = ext_rv64m_smt(ctx, &regs, op, d, s1, s2, imm);

		Z3_dec_ref(ctx, imm);
		ASSERT(handled, "smt: unknown opcode\n");
		smt_pin_x0(ctx, &regs);
	}

	return regs;
}

// catch any error reported through the Z3 error handler.
static thread_local char g_err_buf[512];
static thread_local bool g_err_set = false;
static void z3_error_cb(Z3_context c, Z3_error_code ec) {
	Z3_string msg = Z3_get_error_msg(c, ec);
	snprintf(g_err_buf, sizeof(g_err_buf), "%s", msg ? msg : "z3 error");
	g_err_set = true;
}

smt_result smt_eq(const cpu_program* a, const cpu_program* b, u64 live_outs) {
	smt_result r = {};

	Z3_config cfg = Z3_mk_config();
	Z3_context ctx = Z3_mk_context_rc(cfg);
	Z3_del_config(cfg);
	Z3_set_error_handler(ctx, z3_error_cb);
	g_err_set = false;

	Z3_params params = Z3_mk_params(ctx);
	Z3_params_inc_ref(ctx, params);
	Z3_symbol timeout_sym = Z3_mk_string_symbol(ctx, "timeout");
	Z3_params_set_uint(ctx, params, timeout_sym, SMT_TIMEOUT_MS);

	smt_state in = smt_make_input_state(ctx);
	smt_pin_x0(ctx, &in);

	// run first program
	smt_state out_target = smt_run(ctx, &in, a);
	if(g_err_set) {
		r.kind = SMT_ERROR;
		r.error = g_err_buf;
		smt_free_state(ctx, &in);
		smt_free_state(ctx, &out_target);
		Z3_params_dec_ref(ctx, params);
		Z3_del_context(ctx);
		return r;
	}

	// run second program
	smt_state out_rewrite = smt_run(ctx, &in, b);
	if(g_err_set) {
		r.kind = SMT_ERROR;
		r.error = g_err_buf;
		smt_free_state(ctx, &in);
		smt_free_state(ctx, &out_target);
		smt_free_state(ctx, &out_rewrite);
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
			Z3_ast eq = Z3_mk_eq(ctx, out_target.r[reg], out_rewrite.r[reg]);
			Z3_ast neq = Z3_mk_not(ctx, eq);
			Z3_inc_ref(ctx, neq);
			disjuncts[n_disj++] = neq;
		}
	}

	if(n_disj == 0) {
		r.kind = SMT_EQUIVALENT;
		r.solve_ms = 0;
		smt_free_state(ctx, &in);
		smt_free_state(ctx, &out_target);
		smt_free_state(ctx, &out_rewrite);
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

	const f64 t0 = get_time_ms();
	Z3_lbool chk = Z3_solver_check(ctx, solver);
	r.solve_ms = get_time_ms() - t0;

	switch(chk) {
		case Z3_L_FALSE: r.kind = SMT_EQUIVALENT; break;
		case Z3_L_TRUE: {
			Z3_model m = Z3_solver_get_model(ctx, solver);
			Z3_model_inc_ref(ctx, m);
			for(u32 i = 0; i < 32; ++i) {
				Z3_ast v = nullptr;
				if(Z3_model_eval(ctx, m, in.r[i], true, &v) && v) {
					Z3_inc_ref(ctx, v);
					uint64_t raw = 0;
					r.counterexample.regs[i] = Z3_get_numeral_uint64(ctx, v, &raw) ? raw : 0;
					Z3_dec_ref(ctx, v);
				} else {
					r.counterexample.regs[i] = 0;
				}
			}
			r.counterexample.regs[0] = 0;
			r.kind = SMT_COUNTEREXAMPLE;
			Z3_model_dec_ref(ctx, m);
			break;
		}
		case Z3_L_UNDEF:
		default: r.kind = SMT_TIMEOUT; break;
	}

	if(g_err_set && r.kind != SMT_COUNTEREXAMPLE) {
		r.kind = SMT_ERROR;
		r.error = g_err_buf;
	}

	Z3_dec_ref(ctx, formula);
	Z3_solver_dec_ref(ctx, solver);
	smt_free_state(ctx, &in);
	smt_free_state(ctx, &out_target);
	smt_free_state(ctx, &out_rewrite);
	Z3_params_dec_ref(ctx, params);
	Z3_del_context(ctx);
	return r;
}
