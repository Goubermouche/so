#ifndef DRIVER_CUH
#define DRIVER_CUH

#include "int/cpu.cuh"
#include "int/instruction.cuh"

namespace sup {
	static constexpr u32 MCMC_PROG_LEN = 16;
	static constexpr u32 MCMC_N_TESTS = 32;
	static constexpr u32 N_WARPS_PER_BLOCK = 8;
	static constexpr u32 THREADS_PER_BLOCK = N_WARPS_PER_BLOCK * MCMC_N_TESTS;

	struct mcmc_config {
		u64 max_steps;
		f32 beta;
		u64 live_mask;
		u64 master_seed;
		u32 perf_weight;
		u32 correct_weight;
		u32 n_chains;
		u32 test_weights[MCMC_N_TESTS];
		b32 use_bloom;
		b32 seed_from_target;
	};

	struct mcmc_result {
		inst best_prog[MCMC_PROG_LEN];
		u32 best_cost;
		u32 best_correctness;
		u32 best_perf;
		u64 accepted;
		u64 skipped_bloom;
	};

	mcmc_result* mcmc_run_gpu(const inst* target_prog, u32 target_len, const cpu_state* test_in, const mcmc_config& cfg);
} // namespace sup

#endif // #ifndef DRIVER_CUH

