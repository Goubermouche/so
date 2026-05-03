#include "opt/optimize.h"
#include "smt/smt.h"

namespace so {
	void optimize(const str& prog, const config& cfg) {
		so::program parsed = so::program::parse(prog);
		optimize(parsed, cfg);
	}

	void optimize(const program& prog, const config& cfg) {
		using clk = std::chrono::steady_clock;
		using ms  = std::chrono::duration<f64, std::milli>;

		// logging
		const so::u64 live_mask = cfg.live_mask ? cfg.live_mask : prog.live_outs();
		print("source ({} instructions):\n", prog.instructions.size());
		print("{}", prog.to_string());
		print("live mask: { ");
		detail::print_reg_mask(live_mask);
		print(" }\n");
		print("chains: {}\n", cfg.n_chains);
		print("steps/chain: {}\n", cfg.max_steps);
		print("mode: {}\n", cfg.seed_from_target ? "optimize" : "synthesize");

		// init
		cpu_state test_in[MCMC_N_TESTS];
		detail::seed_test_vectors(test_in, cfg.seed);
		mcmc_config mcfg = {
			.max_steps = cfg.max_steps,
			.beta = 0.1f,
			.live_mask = live_mask,
			.master_seed = cfg.seed,
			.perf_weight = 10,
			.correct_weight = (u32)(cfg.seed_from_target ? 4096 : 1),
			.n_chains = cfg.n_chains,
			.seed_from_target = cfg.seed_from_target
		};

		for(u32 i = 0; i < MCMC_N_TESTS; ++i) {
			mcfg.test_weights[i] = 1;
		}

		mcmc_result*  results = nullptr;
		u32           best    = 0;
		verify_report rep     = {};
		u32           iter_count = 0;
		f64           total_smt_ms = 0.0;
		f64           total_gpu_ms = 0.0;

		// timing
		const auto t_start = clk::now();

		// search loop
		for(u32 iter = 0; iter <= cfg.max_hardening_iters; ++iter) {
			mcfg.master_seed = cfg.seed + iter;
			results = mcmc_run_gpu(prog.instructions.data(), (u32)prog.instructions.size(), test_in, mcfg);
			total_gpu_ms += ms(clk::now() - t_start).count();
			iter_count++;
			best = detail::argmin_cost(results, cfg.n_chains);

			// verify program equivalence via smt
			rep = verify_equivalent(prog.instructions.data(), (u32)prog.instructions.size(), results[best].best_prog, MCMC_PROG_LEN, live_mask);
			total_smt_ms += rep.solve_ms;

			if(rep.kind != VERIFY_COUNTEREXAMPLE) {
				break; // optimized or timeout
			}

			// smt counterexample
			if(iter < cfg.max_hardening_iters) {
				const u32 slot = iter % MCMC_N_TESTS;
				test_in[slot] = rep.counterexample;
				mcfg.test_weights[slot] = 4096;
				print("hardening iter: {}\n", iter);
				free(results);
				results = nullptr;
			}
		}

		// report
		print("\n");
		u64 total_accepted = 0;
		u64 total_skipped_bloom = 0;

		for(u32 i = 0; i < cfg.n_chains; ++i) {
			total_accepted += results[i].accepted;
			total_skipped_bloom += results[i].skipped_bloom;
		}

		const u64 total_proposed = (u64)cfg.n_chains * cfg.max_steps;
		const f64 cands_per_sec = (f64)total_proposed / (total_gpu_ms / 1000.0 / iter_count);

		if(iter_count > 1) {
			print("hardened in {} iterations: {}ms gpu + {}ms smt\n", iter_count, total_gpu_ms, total_smt_ms);
		}
		else {
			print("optimized in {}ms {} candidates {}M cand/sec\n", total_gpu_ms, total_proposed, cands_per_sec / 1e6);
		}

		if(mcfg.use_bloom) {
			print("accept {}% bloom-skip {}%\n", 100.0 * (f64)total_accepted / (f64)total_proposed, 100.0 * (f64)total_skipped_bloom / (f64)total_proposed);
		}
		else {
			print("accept {}%\n", 100.0 * (f64)total_accepted / (f64)total_proposed);
		}

		print("best chain: #{}  cost={}  (correct={} perf={})\n", best, results[best].best_cost, results[best].best_correctness, results[best].best_perf);

		// result program
		program live_prog = program::dce(results[best].best_prog, MCMC_PROG_LEN, live_mask);
		print("best program ({} live insn):\n", live_prog.instructions.size());
		print("{}\n", live_prog.to_string());

		// smt outcome
		switch(rep.kind) {
			case so::VERIFY_EQUIVALENT: print("smt: VERIFIED equivalent to target ({}ms total smt)\n", total_smt_ms); break;
			case so::VERIFY_TIMEOUT: print("smt: TIMEOUT after {}ms\n", rep.solve_ms); break;
			case so::VERIFY_ERROR: print("smt: ERROR: {}\n", rep.error ? rep.error : "(unknown)"); break;
			case so::VERIFY_COUNTEREXAMPLE: {
				print("smt: UNVERIFIED after {} hardening iterations: last counterexample:\n", iter_count);
				for(u32 i = 0; i < 16; ++i) {
					u64 v = rep.counterexample.regs[i];
					if(v) {
						print("  {} = {}\n", so::reg_name(i), v);
					}
				}
				break;
			}
		}

		free(results);
	}

	namespace detail {
		void print_reg_mask(u64 mask) {
			bool first = true;

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

		void seed_test_vectors(cpu_state (&test_in)[MCMC_N_TESTS], u64 seed) {
			u64 s = seed ^ 0x9E3779B97F4A7C15ULL;
			for(u32 t = 0; t < MCMC_N_TESTS; ++t) {
				for(u32 i = 0; i < 16; ++i) {
					s ^= s >> 30; s *= 0xBF58476D1CE4E5B9ULL;
					s ^= s >> 27; s *= 0x94D049BB133111EBULL;
					s ^= s >> 31;
					test_in[t].regs[i] = s;
				}
			}
		}

		u32 argmin_cost(const mcmc_result* results, u32 n) {
			u32 best = 0;
			for(u32 i = 1; i < n; ++i) {
				if(results[i].best_cost < results[best].best_cost) best = i;
			}
			return best;
		}
	} // namespace detail
} // namespace so

