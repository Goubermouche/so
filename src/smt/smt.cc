#include "smt/smt.h"
#include "int/instruction.cuh"
#include <z3++.h>

namespace so {
	namespace detail {
		using state_array = std::array<z3::expr, 16>;

		state_array make_input_state(z3::context& ctx) {
			char name[32];

			state_array s = {
				ctx.bv_const("s_rax", 64),
				ctx.bv_const("s_rbx", 64),
				ctx.bv_const("s_rcx", 64),
				ctx.bv_const("s_rdx", 64),
				ctx.bv_const("s_rsi", 64),
				ctx.bv_const("s_rdi", 64),
				ctx.bv_const("s_rbp", 64),
				ctx.bv_const("s_rsp", 64),
				ctx.bv_const("s_r8",  64),
				ctx.bv_const("s_r9",  64),
				ctx.bv_const("s_r10", 64),
				ctx.bv_const("s_r11", 64),
				ctx.bv_const("s_r12", 64),
				ctx.bv_const("s_r13", 64),
				ctx.bv_const("s_r14", 64),
				ctx.bv_const("s_r15", 64),
			};

			(void)name;
			return s;
		}

		u32 lea_log2_for_scale(opcode op) {
			switch(op) {
				case OP_LEA_R64_R64_R64_S1: return 0;
				case OP_LEA_R64_R64_R64_S2: return 1;
				case OP_LEA_R64_R64_R64_S4: return 2;
				case OP_LEA_R64_R64_R64_S8: return 3;
				default: return 0;
			}
		}

		state_array symbolic_run(
			z3::context& ctx,
			const state_array& in,
			const inst* prog,
			u32 prog_len,
			const char** unsupported_opcode
		) {
			state_array regs = in;

			for(u32 i = 0; i < prog_len; ++i) {
				const inst& ins = prog[i];
				const u32 d = (u32)ins.operands[0].reg;
				const u32 s = (u32)ins.operands[1].reg;

				switch(ins.op) {
					case OP_NOP:          break;
					case OP_MOV_R64_R64:  regs[d] = regs[s]; break;
					case OP_MOV_R64_I64:  regs[d] = ctx.bv_val((u64)ins.operands[1].i, 64); break;
					case OP_ADD_R64_R64:  regs[d] = regs[d] + regs[s]; break;
					case OP_ADD_R64_I64:  regs[d] = regs[d] + ctx.bv_val((u64)ins.operands[1].i, 64); break;
					case OP_SUB_R64_R64:  regs[d] = regs[d] - regs[s]; break;
					case OP_SUB_R64_I64:  regs[d] = regs[d] - ctx.bv_val((u64)ins.operands[1].i, 64); break;
					case OP_NEG_R64:      regs[d] = -regs[d]; break;  // bvneg
					case OP_IMUL_R64_R64: regs[d] = regs[d] * regs[s]; break;
					case OP_IMUL_R64_I64: regs[d] = regs[d] * ctx.bv_val((u64)ins.operands[1].i, 64); break;
					case OP_AND_R64_R64:  regs[d] = regs[d] & regs[s]; break;
					case OP_AND_R64_I64:  regs[d] = regs[d] & ctx.bv_val((u64)ins.operands[1].i, 64); break;
					case OP_OR_R64_R64:   regs[d] = regs[d] | regs[s]; break;
					case OP_OR_R64_I64:   regs[d] = regs[d] | ctx.bv_val((u64)ins.operands[1].i, 64); break;
					case OP_XOR_R64_R64:  regs[d] = regs[d] ^ regs[s]; break;
					case OP_XOR_R64_I64:  regs[d] = regs[d] ^ ctx.bv_val((u64)ins.operands[1].i, 64); break;
					case OP_NOT_R64:      regs[d] = ~regs[d]; break;
					case OP_SHL_R64_I64: {
						const u32 cnt = (u32)(ins.operands[1].i & 0x3F);
						regs[d] = z3::shl(regs[d], ctx.bv_val(cnt, 64));
						break;
					}
					case OP_SHR_R64_I64: {
						const u32 cnt = (u32)(ins.operands[1].i & 0x3F);
						regs[d] = z3::lshr(regs[d], ctx.bv_val(cnt, 64));
						break;
					}
					case OP_SAR_R64_I64: {
						const u32 cnt = (u32)(ins.operands[1].i & 0x3F);
						regs[d] = z3::ashr(regs[d], ctx.bv_val(cnt, 64));
						break;
					}
					case OP_ROL_R64_I64: {
						const u32 cnt = (u32)(ins.operands[1].i & 0x3F);
						regs[d] = (cnt == 0) ? regs[d] : regs[d].rotate_left(cnt);
						break;
					}
					case OP_ROR_R64_I64: {
						const u32 cnt = (u32)(ins.operands[1].i & 0x3F);
						regs[d] = (cnt == 0) ? regs[d] : regs[d].rotate_right(cnt);
						break;
					}
					case OP_LEA_R64_R64_R64_S1:
					case OP_LEA_R64_R64_R64_S2:
					case OP_LEA_R64_R64_R64_S4:
					case OP_LEA_R64_R64_R64_S8: {
						const u32 base_idx = (u32)ins.operands[1].reg;
						const u32 index_idx = (u32)ins.operands[2].reg;
						const u32 sh = lea_log2_for_scale(ins.op);
						const z3::expr scaled = sh ? z3::shl(regs[index_idx], ctx.bv_val(sh, 64)) : regs[index_idx];
						regs[d] = regs[base_idx] + scaled;
						break;
					}
					case OP_COUNT: if(unsupported_opcode) *unsupported_opcode = "OP_COUNT (sentinel)"; break;
				}
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

			// same input state for both runs
			detail::state_array in = detail::make_input_state(ctx);
			const char* err = nullptr;
			detail::state_array out_target  = detail::symbolic_run(ctx, in, target,  target_len,  &err);

			if(err) {
				r.kind = VERIFY_ERROR;
				r.error = err;
				return r;
			}

			detail::state_array out_rewrite = detail::symbolic_run(ctx, in, rewrite, rewrite_len, &err);

			if(err) {
				r.kind = VERIFY_ERROR;
				r.error = err;
				return r;
			}

			// build the disequality clause over live-out registers
			z3::expr_vector disjuncts(ctx);

			for(u32 reg = 0; reg < 16; ++reg) {
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
				case z3::unsat: {
					r.kind = VERIFY_EQUIVALENT;
					return r;
				}
				case z3::sat: {
					// counterexample
					z3::model m = solver.get_model();

					for(u32 i = 0; i < 16; ++i) {
						z3::expr v = m.eval(in[i], true);
						u64 raw = 0;

						if(v.is_numeral_u64(raw)) {
							r.counterexample.regs[i] = (u64)raw;
						}
						else {
							r.counterexample.regs[i] = 0;
						}
					}

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
			r.error = e.msg();
			return r;
		}
	}
} // namespace so

