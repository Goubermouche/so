#include "opt/optimize.h"
#include "opt/batch_runner.cuh"
#include <chrono>

namespace sup {
	void optimize(const str& prog, const config& cfg) {
		sup::program parsed = sup::program::parse(prog);
		optimize(parsed, cfg);
	}

	void optimize(const program& prog, const config& cfg) {
		detail::optimizer opt(prog, cfg);
		opt.run();
	}

	namespace detail {
		static cpu_state host_run(const inst* prog, u32 prog_len, const cpu_state& in) {
			cpu_state out = in;
			out.regs[0] = 0;
			run_program_lane(out.regs, prog, prog_len);
			return out;
		}

		optimizer::optimizer(const program& prog, const config& cfg) :
			m_prog(prog),
			m_cfg(cfg),
			m_live_in(0),
			m_live_out(cfg.live_mask ? cfg.live_mask : prog.live_outs()),
			m_best_len(0),
			m_total_candidates(0),
			m_total_gpu_passes(0),
			m_total_gpu_ms(0.0),
			m_total_smt_ms(0.0),
			m_total_smt_calls(0)
		{
			m_live_in = compute_live_in(prog.instructions.data(), (u32)prog.instructions.size());
		}

		optimizer::~optimizer() {}

		void optimizer::run() {
			log_startup();
			seed_test_vectors();

			if(m_gpu.init(m_cfg.gpu_chunk_size) != 0) {
				print("error: gpu_runner::init failed\n");
				return;
			}

			b32 found = false;
			for(u32 L = 1; L <= m_cfg.max_prog_len; ++L) {
				print("> searching length\n", L);
				if(run_length(L)) {
					found = true;
					m_best_len = L;
					break;
				}
			}

			log_results(found);
		}

		void optimizer::log_startup() const {
			print("> source ({} instructions):\n", m_prog.instructions.size());
			print("{}", m_prog.to_string());
			print("> live-in:  { "); print_reg_mask(m_live_in);  print(" }\n");
			print("> live-out: { "); print_reg_mask(m_live_out); print(" }\n");
			u32 effective_mask = m_cfg.ext_mask | EXT_RV32I;

			if(effective_mask & EXT_RV64M) {
				effective_mask |= EXT_RV32M;
			}

			print("> ext mask: 0x{} (RV32I{}{}{})\n",
				effective_mask,
				(effective_mask & EXT_RV64I) ? "+RV64I" : "",
				(effective_mask & EXT_RV32M) ? "+RV32M" : "",
				(effective_mask & EXT_RV64M) ? "+RV64M" : "");
			print("> max prog len: {}\n", m_cfg.max_prog_len);
			print("> batch size:   {}\n", m_cfg.batch_size);
		}

		void optimizer::print_reg_mask(u64 mask) const {
			b32 first = true;

			for(u32 r = 0; r < 32; ++r) {
				if(mask & (1ULL << r)) {
					print("{}{}", first ? "" : ",", reg_name(r));
					first = false;
				}
			}

			if(first) {
				print("(none)");
			}
		}

		void optimizer::seed_test_vectors() {
			// 32 random test vectors at start. The CEGIS loop adds counterexamples
			// in subsequent slots.
			const u32 n_initial = 32;
			u64 s = m_cfg.seed ^ 0x9E3779B97F4A7C15ULL;

			for(u32 t = 0; t < n_initial; ++t) {
				cpu_state in = {};

				for(u32 i = 0; i < 32; ++i) {
					s ^= s >> 30; s *= 0xBF58476D1CE4E5B9ULL;
					s ^= s >> 27; s *= 0x94D049BB133111EBULL;
					s ^= s >> 31;
					in.regs[i] = s;
				}

				in.regs[0] = 0; // x0 invariant
				m_test_in[t] = in;
				m_target_out[t] = host_run(m_prog.instructions.data(), (u32)m_prog.instructions.size(), in);
			}

			m_n_tests = n_initial;
		}

		struct survivor_set {
			arr<u32> indices;
		};

		void optimizer::filter_batch(const arr<candidate<SYNTH_PROG_LEN>>& cands) {
			const u64 N = cands.size();

			if(N == 0) {
				return;
			}

			arr<inst> flat;
			flat.resize(N * SYNTH_PROG_LEN);

			for(u64 i = 0; i < N; ++i) {
				const candidate<SYNTH_PROG_LEN>& c = cands[i];

				for(u32 j = 0; j < SYNTH_PROG_LEN; ++j) {
					if(j < c.len) {
						flat[i * SYNTH_PROG_LEN + j] = c.code[j];
					}
					else {
						inst nop = {};
						nop.op = OP_NOP;
						flat[i * SYNTH_PROG_LEN + j] = nop;
					}
				}
			}

			synth_config gcfg;
			gcfg.live_mask = m_live_out;
			gcfg.n_tests = m_n_tests;
			gcfg.prog_len = cands[0].len;
			arr<synth_result> results;
			results.resize(N);
			f64 ms = 0.0;
			m_gpu.run(flat.data(), N, m_test_in, m_target_out, gcfg, results.data(), &ms);
			m_total_gpu_ms += ms;
			m_total_candidates += N;
			++m_total_gpu_passes;

			// any candidate that passed all tests is forwarded to SMT
			u64 ok_count = 0;
			for(u64 i = 0; i < N; ++i) {
				if(results[i].pass_count == m_n_tests) {
					++ok_count;
					// SMT-verify
					const inst* rw = flat.data() + i * SYNTH_PROG_LEN;
					const u32 rw_len = cands[i].len;
					const auto t0 = std::chrono::steady_clock::now();
					program_slice a = { m_prog.instructions.data(), (u32)m_prog.instructions.size() };
					program_slice b = { rw, rw_len };
					smt_verify_report rep = smt_eq(&a, &b, m_live_out);
					const auto t1 = std::chrono::steady_clock::now();
					m_total_smt_ms += std::chrono::duration<f64, std::milli>(t1 - t0).count();
					++m_total_smt_calls;

					if(rep.kind == VERIFY_EQUIVALENT) {
						m_rep = rep;
						m_best_prog.assign(rw, rw + rw_len);
						return;
					}
					else if(rep.kind == VERIFY_COUNTEREXAMPLE) {
						// add the counterexample, then ABORT this batch
						if(m_n_tests < SYNTH_N_TESTS) {
							const u32 slot = m_n_tests++;
							m_test_in[slot]    = rep.counterexample;
							m_target_out[slot] = host_run(m_prog.instructions.data(), (u32)m_prog.instructions.size(), rep.counterexample);
							print("  smt counterexample added (now {} tests)\n", m_n_tests);
						}
						else {
							print("  smt counterexample dropped (test buffer full)\n");
						}

						print("  batch: {} cands -> {} passed GPU -> aborting (counterexample)\n", N, ok_count);
						return;
					}
					else {
						print("  smt {}: dropping candidate\n", rep.kind == VERIFY_TIMEOUT ? "TIMEOUT" : "ERROR");
					}
				}
			}

			print("  batch: {} cands -> {} passed GPU -> 0 verified\n", N, ok_count);
		}

		b32 optimizer::run_length(u32 L) {
			u32 effective_mask = m_cfg.ext_mask | EXT_RV32I;

			if(effective_mask & EXT_RV64M) {
				effective_mask |= EXT_RV32M;
			}

			const opcode_pool pool = build_opcode_pool(effective_mask);
			const imm_pool imms = build_default_imm_pool();
			print("  opcode pool: {} ops\n", pool.n_ops);
			u32 max_scratch = 5 + L; if(max_scratch > 32) max_scratch = 32;

			using clk = std::chrono::steady_clock;

			// regenerate candidates if the test set grows
			u32 cegis_iter = 0;

			while(cegis_iter < m_cfg.max_cegis_iters) {
				const u32 prev_n_tests = m_n_tests;

				// enumerate in chunks.
				arr<candidate<SYNTH_PROG_LEN>> cands;
				cands.reserve(m_cfg.batch_size);

				const auto t_start = clk::now();
				enumerate_programs<SYNTH_PROG_LEN>(
					pool, imms,
					m_live_in, m_live_out,
					L, max_scratch,
					cands, m_cfg.batch_size
				);

				print("  cegis iter {}: enumerated {} candidates ({}ms)\n",
					cegis_iter, cands.size(),
					std::chrono::duration<f64, std::milli>(clk::now() - t_start).count());

				if(cands.empty()) {
					return false;
				}

				filter_batch(cands);

				if(!m_best_prog.empty()) {
					return true;
				}

				// if no new counterexample was added, we exhausted the
				// candidate space at this L without finding equivalence
				if(m_n_tests == prev_n_tests) {
					print("  no counterexamples found and no equivalent program - length {} is insufficient\n", L);
					return false;
				}

				++cegis_iter;
			}

			print("  cegis iter limit hit at length {}\n", L);
			return false;
		}

		void optimizer::log_results(b32 found) const {
			print("> finished\n");
			print("  total candidates evaluated: {}\n", m_total_candidates);
			print("  total gpu time:             {}ms\n", m_total_gpu_ms);
			print("  total smt time:             {}ms ({} calls)\n", m_total_smt_ms, m_total_smt_calls);

			if(m_total_gpu_ms > 0) {
				const f64 cps = (f64)m_total_candidates / (m_total_gpu_ms / 1000.0);
				print("  gpu throughput:             {}M cand/sec\n", cps / 1e6);
			}

			if(found) {
				program live_prog;
				live_prog.instructions.assign(m_best_prog.begin(), m_best_prog.end());
				print("> best program ({} instructions, SMT VERIFIED equivalent):\n", m_best_len);
				print("{}", live_prog.to_string());
			}
			else {
				print("> no equivalent program found within length {}\n", m_cfg.max_prog_len);
			}
		}
	} // namespace detail
} // namespace sup

