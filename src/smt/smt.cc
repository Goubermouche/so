#include "smt/smt.h"
#include "int/instruction.cuh"
#include "ext/rv32i/smt.cuh"
#include "ext/rv64i/smt.cuh"
#include "ext/rv32m/smt.cuh"
#include "ext/rv64m/smt.cuh"
#include <z3++.h>

namespace sup {
	namespace detail {
		smt_state make_input_state(z3::context& ctx) {
			smt_state a = {
				ctx.bv_const("s_x0",  64), ctx.bv_const("s_x1",  64),
				ctx.bv_const("s_x2",  64), ctx.bv_const("s_x3",  64),
				ctx.bv_const("s_x4",  64), ctx.bv_const("s_x5",  64),
				ctx.bv_const("s_x6",  64), ctx.bv_const("s_x7",  64),
				ctx.bv_const("s_x8",  64), ctx.bv_const("s_x9",  64),
				ctx.bv_const("s_x10", 64), ctx.bv_const("s_x11", 64),
				ctx.bv_const("s_x12", 64), ctx.bv_const("s_x13", 64),
				ctx.bv_const("s_x14", 64), ctx.bv_const("s_x15", 64),
				ctx.bv_const("s_x16", 64), ctx.bv_const("s_x17", 64),
				ctx.bv_const("s_x18", 64), ctx.bv_const("s_x19", 64),
				ctx.bv_const("s_x20", 64), ctx.bv_const("s_x21", 64),
				ctx.bv_const("s_x22", 64), ctx.bv_const("s_x23", 64),
				ctx.bv_const("s_x24", 64), ctx.bv_const("s_x25", 64),
				ctx.bv_const("s_x26", 64), ctx.bv_const("s_x27", 64),
				ctx.bv_const("s_x28", 64), ctx.bv_const("s_x29", 64),
				ctx.bv_const("s_x30", 64), ctx.bv_const("s_x31", 64),
			};
			return a;
		}

		smt_state symbolic_run(z3::context& ctx, const smt_state& in, const inst* prog, u32 prog_len, const char** unsupported_opcode) {
			smt_state regs = in;
			regs[0] = ctx.bv_val((u64)0, 64); // pin x0 = 0

			for(u32 i = 0; i < prog_len; ++i) {
				const inst& ins = prog[i];
				const u32 op = (u32)ins.op;

				if(op == OP_NOP) {
					continue;
				}

				const inst_spec& spec = INST_DB_HOST.row[op];
				const u32 d = spec.dst_slot >= 0 ? (u32)ins.operands[spec.dst_slot ].reg : 0;
				const u32 s1 = spec.src_slot >= 0 ? (u32)ins.operands[spec.src_slot ].reg : 0;
				const u32 s2 = spec.src2_slot >= 0 ? (u32)ins.operands[spec.src2_slot].reg : 0;
				z3::expr imm = ctx.bv_val((u64)0, 64);

				for(u32 k = 0; k < 4; ++k) {
					if(spec.operands[k] == inst_spec::IMM) {
						imm = ctx.bv_val((u64)ins.operands[k].i, 64);
						break;
					}
				}

				// dispatch through registered extensions in declaration order
				bool handled = false;
				if(!handled) handled = ext_rv32i_smt(ctx, regs, op, d, s1, s2, imm);
				if(!handled) handled = ext_rv64i_smt(ctx, regs, op, d, s1, s2, imm);
				if(!handled) handled = ext_rv32m_smt(ctx, regs, op, d, s1, s2, imm);
				if(!handled) handled = ext_rv64m_smt(ctx, regs, op, d, s1, s2, imm);

				if(!handled) {
					if(unsupported_opcode) {
						*unsupported_opcode = "opcode not handled by any extension";
					}

					break;
				}

				// re-pin x0 = 0 after every step
				regs[0] = ctx.bv_val((u64)0, 64);
			}

			return regs;
		}
	} // namespace detail

	verify_report verify_equivalent(
		const inst* target, u32 target_len,
		const inst* rewrite, u32 rewrite_len,
		u64 live_outs,
		u32 timeout_ms
	) {
		verify_report r = {};

		try {
			z3::context ctx;
			z3::params  params(ctx);
			params.set(":timeout", timeout_ms);

			smt_state in = detail::make_input_state(ctx);
			in[0] = ctx.bv_val((u64)0, 64);

			const char* err = nullptr;
			smt_state out_target  = detail::symbolic_run(ctx, in, target,  target_len,  &err);

			if(err) {
				r.kind = VERIFY_ERROR;
				r.error = err;
				return r;
			}

			smt_state out_rewrite = detail::symbolic_run(ctx, in, rewrite, rewrite_len, &err);

			if(err) {
				r.kind = VERIFY_ERROR;
				r.error = err;
				return r;
			}

			z3::expr_vector disjuncts(ctx);

			for(u32 reg = 0; reg < 32; ++reg) {
				if(reg == 0) {
					continue;
				}

				if(live_outs & (1ULL << reg)) {
					disjuncts.push_back(out_target[reg] != out_rewrite[reg]);
				}
			}

			if(disjuncts.empty()) {
				r.kind = VERIFY_EQUIVALENT;
				r.solve_ms = 0;
				return r;
			}

			z3::solver solver(ctx);
			solver.set(params);
			solver.add(z3::mk_or(disjuncts));

			const auto t0 = std::chrono::high_resolution_clock::now();
			const z3::check_result chk = solver.check();
			const auto t1 = std::chrono::high_resolution_clock::now();
			r.solve_ms = std::chrono::duration<f64, std::milli>(t1 - t0).count();

			switch(chk) {
				case z3::unsat: r.kind = VERIFY_EQUIVALENT; return r;
				case z3::sat: {
					z3::model m = solver.get_model();

					for(u32 i = 0; i < 32; ++i) {
						z3::expr v = m.eval(in[i], true);
						u64 raw = 0;
						r.counterexample.regs[i] = v.is_numeral_u64(raw) ? raw : 0;
					}

					r.counterexample.regs[0] = 0;
					r.kind = VERIFY_COUNTEREXAMPLE;
					return r;
				}
				case z3::unknown:
				default:
					r.kind = VERIFY_TIMEOUT;
					return r;
			}
		}
		catch(const z3::exception& e) {
			r.kind = VERIFY_ERROR;
			static thread_local char err_buf[512];
			std::snprintf(err_buf, sizeof(err_buf), "%s", e.msg());
			r.error = err_buf;
			return r;
		}
	}
} // namespace sup

