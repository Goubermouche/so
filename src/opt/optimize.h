#ifndef OPTIMIZE_H
#define OPTIMIZE_H

#include "int/program.h"
#include "opt/driver.cuh"

namespace so {
	struct config {
		u64 live_mask = 0;
		u64 max_steps = 200'000;
		u64 seed      = 1;
		u32 n_chains  = 256;
		bool seed_from_target = false;
		u32 max_hardening_iters = 3;
	};

	void optimize(const str& prog, const config& cfg = {});
	void optimize(const program& prog, const config& cfg = {});

	namespace detail {
		void print_reg_mask(u64 mask);
		void seed_test_vectors(cpu_state (&test_in)[MCMC_N_TESTS], u64 seed);
		u32 argmin_cost(const mcmc_result* results, u32 n);
	} // namespace detail
} // namespace so

#endif // #ifndef OPTIMIZE_H

