#include "smt/smt.h"
#include "extensions/rv32i/smt.h"
#include "extensions/rv32m/smt.h"
#include "extensions/rv64i/smt.h"
#include "extensions/rv64m/smt.h"
#include "util/type.h"

// thread-local Z3 error capture
static thread_local bool g_err_set = false;

static void z3_error_cb(Z3_context c, Z3_error_code ec) {
	Z3_string msg = Z3_get_error_msg(c, ec);
	fprintf(stderr, "%s", msg ? msg : "z3 error");
	g_err_set = true;
}

SMT_Result smt_equiv(Program* a, Program* b, U64 live_outs) {
	F64 t0 = get_time_ms();
	SMT_Result r = {};

	// init Z3
	Z3_config cfg = Z3_mk_config();
	Z3_context ctx = Z3_mk_context(cfg);
	Z3_del_config(cfg);
	Z3_set_error_handler(ctx, z3_error_cb);
	g_err_set = false;

	Z3_params params = Z3_mk_params(ctx);
	Z3_params_inc_ref(ctx, params);
	Z3_symbol timeout_sym = Z3_mk_string_symbol(ctx, "timeout");
	Z3_params_set_uint(ctx, params, timeout_sym, (U32)SMT_TimeoutMS);

	// make input state
	SMT_State in = smt_make_input_state(ctx);
	smt_pin_x0(ctx, &in);

	// run first program
	SMT_State out_target = smt_run(ctx, &in, a);
	if(g_err_set) {
		r.type = SMT_ResultType_ERROR;
		smt_free_state(ctx, &in);
		smt_free_state(ctx, &out_target);
		Z3_params_dec_ref(ctx, params);
		Z3_del_context(ctx);
		return r;
	}

	// run second program
	SMT_State out_rewrite = smt_run(ctx, &in, b);
	if(g_err_set) {
		r.type = SMT_ResultType_ERROR;
		smt_free_state(ctx, &in);
		smt_free_state(ctx, &out_target);
		smt_free_state(ctx, &out_rewrite);
		Z3_params_dec_ref(ctx, params);
		Z3_del_context(ctx);
		return r;
	}

	// OR over live regs of (out_target[reg] != out_rewrite[reg])
	Z3_ast disjuncts[32];
	U32 n_disj = 0;
	for(U32 reg = 0; reg < 32; ++reg) {
		if(reg == 0) continue;
		if(live_outs & (1ULL << reg)) {
			Z3_ast eq = Z3_mk_eq(ctx, out_target.r[reg], out_rewrite.r[reg]);
			Z3_ast neq = Z3_mk_not(ctx, eq);
			Z3_inc_ref(ctx, neq);
			disjuncts[n_disj++] = neq;
		}
	}

	if(n_disj == 0) {
		// trivially equivalent
		r.type = SMT_ResultType_EQUIVALENT;
		smt_free_state(ctx, &in);
		smt_free_state(ctx, &out_target);
		smt_free_state(ctx, &out_rewrite);
		Z3_params_dec_ref(ctx, params);
		Z3_del_context(ctx);
		return r;
	}

	Z3_ast formula = Z3_mk_or(ctx, n_disj, disjuncts);
	Z3_inc_ref(ctx, formula);
	for(U32 i = 0; i < n_disj; ++i) Z3_dec_ref(ctx, disjuncts[i]);

	// solve
	Z3_solver solver = Z3_mk_solver(ctx);
	Z3_solver_inc_ref(ctx, solver);
	Z3_solver_set_params(ctx, solver, params);
	Z3_solver_assert(ctx, solver, formula);
	Z3_lbool chk = Z3_solver_check(ctx, solver);

	switch(chk) {
		case Z3_L_FALSE: r.type = SMT_ResultType_EQUIVALENT; break;
		case Z3_L_TRUE: {
			// programs are not equivalent => build counterexample
			Z3_model m = Z3_solver_get_model(ctx, solver);
			Z3_model_inc_ref(ctx, m);
			for(U32 i = 0; i < 32; ++i) {
				if(i == 0) {
					r.counterexample.regs[i] = 0;
					continue;
				}
				Z3_ast v = 0;
				if(Z3_model_eval(ctx, m, in.r[i], true, &v) && v) {
					Z3_inc_ref(ctx, v);
					uint64_t raw = 0;
					r.counterexample.regs[i] = Z3_get_numeral_uint64(ctx, v, &raw) ? raw : 0;
					Z3_dec_ref(ctx, v);
				} else {
					r.counterexample.regs[i] = 0;
				}
			}
			r.type = SMT_ResultType_COUNTEREXAMPLE;
			Z3_model_dec_ref(ctx, m);
			break;
		}
		case Z3_L_UNDEF:
		default: r.type = SMT_ResultType_TIMEOUT; break;
	}

	if(g_err_set && r.type != SMT_ResultType_COUNTEREXAMPLE) {
		r.type = SMT_ResultType_ERROR;
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

Z3_ast smt_low6(Z3_context ctx, Z3_ast v) {
	Z3_sort s64 = Z3_mk_bv_sort(ctx, 64);
	Z3_ast mask = Z3_mk_unsigned_int64(ctx, 0x3F, s64);
	return Z3_mk_bvand(ctx, v, mask);
}

Z3_ast smt_sext_w(Z3_context ctx, Z3_ast v64) {
	Z3_ast lo32 = Z3_mk_extract(ctx, 31, 0, v64);
	return Z3_mk_sign_ext(ctx, 32, lo32);
}

Z3_ast smt_bv32(Z3_context ctx, U64 v) {
	Z3_sort s32 = Z3_mk_bv_sort(ctx, 32);
	return Z3_mk_unsigned_int64(ctx, v, s32);
}

Z3_ast smt_bv64(Z3_context ctx, U64 v) {
	Z3_sort s64 = Z3_mk_bv_sort(ctx, 64);
	return Z3_mk_unsigned_int64(ctx, v, s64);
}

Z3_ast smt_ite_bool_to_bv64(Z3_context ctx, Z3_ast cond) {
	return Z3_mk_ite(ctx, cond, smt_bv64(ctx, 1), smt_bv64(ctx, 0));
}

Z3_ast smt_mk_bv64_const(Z3_context ctx, const C8* name) {
	Z3_sort s64 = Z3_mk_bv_sort(ctx, 64);
	Z3_symbol sym = Z3_mk_string_symbol(ctx, name);
	Z3_ast c = Z3_mk_const(ctx, sym, s64);
	Z3_inc_ref(ctx, c);
	return c;
}

void smt_wr(Z3_context ctx, SMT_State* state, U32 d, Z3_ast v) {
	if(d == 0) { return; }
	Z3_inc_ref(ctx, v);
	if(state->r[d]) { Z3_dec_ref(ctx, state->r[d]); }
	state->r[d] = v;
}

void smt_pin_x0(Z3_context ctx, SMT_State* state) {
	Z3_sort s64 = Z3_mk_bv_sort(ctx, 64);
	Z3_ast zero = Z3_mk_unsigned_int64(ctx, 0, s64);
	Z3_inc_ref(ctx, zero);
	if(state->r[0]) Z3_dec_ref(ctx, state->r[0]);
	state->r[0] = zero;
}

void smt_free_state(Z3_context ctx, SMT_State* state) {
	for(U32 i = 0; i < 32; ++i) {
		if(state->r[i]) {
			Z3_dec_ref(ctx, state->r[i]);
			state->r[i] = 0;
		}
	}
}

SMT_State smt_clone_state(Z3_context ctx, SMT_State* src) {
	SMT_State out = {};
	for(U32 i = 0; i < 32; ++i) {
		out.r[i] = src->r[i];
		if(out.r[i]) Z3_inc_ref(ctx, out.r[i]);
	}
	return out;
}

SMT_State smt_make_input_state(Z3_context ctx) {
	static const C8* names[32] = {
		"s_x0",	 "s_x1",	"s_x2",	 "s_x3",	"s_x4",	 "s_x5",	"s_x6",	 "s_x7",
		"s_x8",	 "s_x9",	"s_x10", "s_x11", "s_x12", "s_x13", "s_x14", "s_x15",
		"s_x16", "s_x17", "s_x18", "s_x19", "s_x20", "s_x21", "s_x22", "s_x23",
		"s_x24", "s_x25", "s_x26", "s_x27", "s_x28", "s_x29", "s_x30", "s_x31",
	};

	SMT_State a = {};
	for(U32 i = 0; i < 32; ++i) { a.r[i] = smt_mk_bv64_const(ctx, names[i]); }
	return a;
}

SMT_State smt_run(Z3_context ctx, SMT_State* in, Program* p) {
	SMT_State regs = smt_clone_state(ctx, in);
	smt_pin_x0(ctx, &regs);
	Z3_sort s64 = Z3_mk_bv_sort(ctx, 64);

	for(U32 i = 0; i < p->size; ++i) {
		Instruction& ins = p->instructions[i];
		U32 op = (U32)ins.op;

		if(op == InstructionOpcode_Nop) { continue; }

		// get operands
		InstructionInfo* info = &instruction_db_host.row[op];

		Z3_ast imm = Z3_mk_unsigned_int64(ctx, 0, s64);
		Z3_inc_ref(ctx, imm);

		// init operands
		for(U32 k = 0; k < 4; ++k) {
			if(info->operands[k] == InstructionOperandType_Imm) {
				Z3_ast new_imm = Z3_mk_unsigned_int64(ctx, (U64)ins.operands[k].imm, s64);
				Z3_inc_ref(ctx, new_imm);
				Z3_dec_ref(ctx, imm);
				imm = new_imm;
				break;
			}
		}

		SMT_Decode dec = {};
		dec.op = op;
		dec.d = info->dst_slot >= 0 ? ins.operands[info->dst_slot].reg : 0;
		dec.s1 = info->src_slot >= 0 ? ins.operands[info->src_slot].reg : 0;
		dec.s2 = info->src2_slot >= 0 ? ins.operands[info->src2_slot].reg : 0;
		dec.imm = imm;

		// build solver
		B32 handled = false;
		if(!handled) handled = ext_rv32i_smt(ctx, &regs, &dec);
		if(!handled) handled = ext_rv64i_smt(ctx, &regs, &dec);
		if(!handled) handled = ext_rv32m_smt(ctx, &regs, &dec);
		if(!handled) handled = ext_rv64m_smt(ctx, &regs, &dec);

		Z3_dec_ref(ctx, imm);
		Assert(handled, "smt: unknown InstructionOpcode\n");
		smt_pin_x0(ctx, &regs);
	}

	return regs;
}