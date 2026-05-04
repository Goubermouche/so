#include "opt/optimize.h"
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
		optimizer::optimizer(const program& prog, const config& cfg) :
			m_prog(prog),
			m_cfg(cfg),
			m_live_mask(cfg.live_mask ? cfg.live_mask : prog.live_outs()),
			m_results(nullptr),
			m_best(0),
			m_rep({}),
			m_iter_count(0),
			m_total_smt_ms(0.0),
			m_total_gpu_ms(0.0)
		{}

		optimizer::~optimizer() {
			if(m_results) {
				free(m_results);
			}
		}

		void optimizer::run() {
			log_startup();
			seed_test_vectors();
			setup_mcmc_config();
			run_search_loop();
			log_results();
		}

		void optimizer::log_startup() const {
			print("source ({} instructions):\n", m_prog.instructions.size());
			print("{}", m_prog.to_string());
			print("live mask: { ");
			print_reg_mask(m_live_mask);
			print(" }\n");
			print("chains: {}\n", m_cfg.n_chains);
			print("steps/chain: {}\n", m_cfg.max_steps);
			print("mode: {}\n", m_cfg.seed_from_target ? "optimize" : "synthesize");
		}

		void optimizer::print_reg_mask(u64 mask) const {
			b32 first = true;

			for(u32 r = 0; r < 16; ++r) {
				if(mask & (1ull << r)) {
					print("{}{}", first ? "" : ",", reg_name(r));
					first = false;
				}
			}

			if(first) {
				print("(none)");
			}
		}

		void optimizer::seed_test_vectors() {
			u64 s = m_cfg.seed ^ 0x9E3779B97F4A7C15ULL;

			for(u32 t = 0; t < MCMC_N_TESTS; ++t) {
				for(u32 i = 0; i < 16; ++i) {
					s ^= s >> 30; s *= 0xBF58476D1CE4E5B9ULL;
					s ^= s >> 27; s *= 0x94D049BB133111EBULL;
					s ^= s >> 31;
					m_test_in[t].regs[i] = s;
				}
			}
		}

		void optimizer::setup_mcmc_config() {
			m_mcfg = {
				.max_steps = m_cfg.max_steps,
				.beta = 0.1f,
				.live_mask = m_live_mask,
				.master_seed = m_cfg.seed,
				.perf_weight = 10,
				.correct_weight = (u32)(m_cfg.seed_from_target ? 4096 : 1),
				.n_chains = m_cfg.n_chains,
				.seed_from_target =m_cfg.seed_from_target
			};

			for(u32 i = 0; i < MCMC_N_TESTS; ++i) {
				m_mcfg.test_weights[i] = 1;
			}
		}

		void optimizer::run_search_loop() {
			using clk = std::chrono::steady_clock;
			using ms = std::chrono::duration<f64, std::milli>;

			const auto t_start = clk::now();

			for(u32 iter = 0; iter <= m_cfg.max_hardening_iters; ++iter) {
				m_mcfg.master_seed = m_cfg.seed + iter;
				m_results = mcmc_run_gpu(m_prog.instructions.data(), (u32)m_prog.instructions.size(), m_test_in, m_mcfg);
				m_total_gpu_ms += ms(clk::now() - t_start).count();
				m_iter_count++;
				m_best = argmin_cost();

				// verify program equivalence via smt
				m_rep = verify_equivalent(m_prog.instructions.data(), (u32)m_prog.instructions.size(), m_results[m_best].best_prog, MCMC_PROG_LEN, m_live_mask);
				m_total_smt_ms += m_rep.solve_ms;

				if(m_rep.kind != VERIFY_COUNTEREXAMPLE) {
					break; // optimized or timeout
				}

				// smt counterexample
				if(iter < m_cfg.max_hardening_iters) {
					const u32 slot = iter % MCMC_N_TESTS;
					m_test_in[slot] = m_rep.counterexample;
					m_mcfg.test_weights[slot] = 4096;
					print("hardening iter: {}\n", iter);

					// free the unverified batch of results to prepare for the next iteration
					free(m_results);
					m_results = nullptr;
				}
			}
		}

		u32 optimizer::argmin_cost() const {
			u32 best_idx = 0;

			for(u32 i = 1; i < m_cfg.n_chains; ++i) {
				if(m_results[i].best_cost < m_results[best_idx].best_cost) {
					best_idx = i;
				}
			}

			return best_idx;
		}

		void optimizer::log_results() const {
			print("\n");
			u64 total_accepted = 0;
			u64 total_skipped_bloom = 0;

			for(u32 i = 0; i < m_cfg.n_chains; ++i) {
				total_accepted += m_results[i].accepted;
				total_skipped_bloom += m_results[i].skipped_bloom;
			}

			const u64 total_proposed = (u64)m_cfg.n_chains * m_cfg.max_steps;
			const f64 cands_per_sec = (f64)total_proposed / (m_total_gpu_ms / 1000.0 / m_iter_count);

			if(m_iter_count > 1) {
				print("hardened in {} iterations: {}ms gpu + {}ms smt\n", m_iter_count, m_total_gpu_ms, m_total_smt_ms);
			}
			else {
				print("optimized in {}ms {} candidates {}M cand/sec\n", m_total_gpu_ms, total_proposed, cands_per_sec / 1e6);
			}

			if(m_mcfg.use_bloom) {
				f64 accept = 100.0 * (f64)total_accepted / (f64)total_proposed;
				f64 skip = 100.0 * (f64)total_skipped_bloom / (f64)total_proposed;
				print("accept {}% bloom-skip {}%\n", accept, skip);
			}
			else {
				print("accept {}%\n", 100.0 * (f64)total_accepted / (f64)total_proposed);
			}

			// result program
			program live_prog = program::dce(m_results[m_best].best_prog, MCMC_PROG_LEN, m_live_mask);
			print("best program ({} live insn):\n", live_prog.instructions.size());
			print("{}\n", live_prog.to_string());

			// smt outcome
			switch(m_rep.kind) {
				case sup::VERIFY_EQUIVALENT: print("smt: VERIFIED equivalent to target ({}ms total smt)\n", m_total_smt_ms); break;
				case sup::VERIFY_TIMEOUT: print("smt: TIMEOUT after {}ms\n", m_rep.solve_ms); break;
				case sup::VERIFY_ERROR: print("smt: ERROR: {}\n", m_rep.error ? m_rep.error : "(unknown)"); break;
				case sup::VERIFY_COUNTEREXAMPLE: {
					print("smt: UNVERIFIED after {} hardening iterations: last counterexample:\n", m_iter_count);
					for(u32 i = 0; i < 16; ++i) {
						u64 v = m_rep.counterexample.regs[i];
						if(v) {
							print("  {} = {}\n", sup::reg_name(i), v);
						}
					}
					break;
				}
			}
		}
	} // namespace detail
} // namespace sup

