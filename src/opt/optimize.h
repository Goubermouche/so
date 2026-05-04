#ifndef OPTIMIZE_H
#define OPTIMIZE_H

#include "opt/driver.cuh"
#include "int/program.h"
#include "smt/smt.h"

namespace sup {
	struct config {
		u64 live_mask = 0;
		u64 max_steps = 200'000;
		u64 seed = 1;
		u32 n_chains  = 256;
		b32 seed_from_target = false;
		u32 max_hardening_iters = 3;
	};

	void optimize(const str& prog, const config& cfg = {});
	void optimize(const program& prog, const config& cfg = {});

	namespace detail {
		struct optimizer {
			optimizer(const program& prog, const config& cfg);
			~optimizer();
			void run();
		private:
			void log_startup() const;
			void print_reg_mask(u64 mask) const;
			void seed_test_vectors();
			void setup_mcmc_config();
			void run_search_loop();
			void log_results() const;
			u32  argmin_cost() const;
		private:
			const program& m_prog;
			const config& m_cfg;
			u64 m_live_mask;
			// mcmc state
			mcmc_config m_mcfg;
			cpu_state m_test_in[MCMC_N_TESTS];
			// search context
			mcmc_result* m_results = nullptr;
			u32 m_best = 0;
			verify_report	m_rep = {};
			u32 m_iter_count = 0;
			f64 m_total_smt_ms = 0.0;
			f64 m_total_gpu_ms = 0.0;
		};
	} // namespace detail
} // namespace sup

#endif // #ifndef OPTIMIZE_H

