#ifndef OPT_OPTIMIZE_H
#define OPT_OPTIMIZE_H

#include "cpu/program.h"
#include "optimize/enumerate.cuh"
#include "optimize/filter.cuh"

namespace sup {
struct optimizer {
	struct options {
		u64 seed = 1;
		u32 ext_mask = EXT_RV32I;
		u64 batch_size = 4000000;
		u32 max_cegis_iters = 8;
	};

	static void run(const program& prog, const options& opt);

private:
	optimizer(const program& prog, const options& opt);
	~optimizer();

	b32 run();
	b32 run_length(u32 len);
	b32 filter_batch(const opt_program* p, u64 p_cnt, u32 len);

	void log_startup();
	void log_results(b32 found);
	void log_stats();
	void init_tests();

private:
	const program& prog;
	const options& opt;
	arena mem; // NOTE: maybe not really worth it here
	// input
	u64 live_in;
	u64 live_out;
	// pass contexts
	opt_enum_ctx enumerate;
	// filter
	opt_filter_ctx filter;
	cpu_state test_in[OPT_FILTER_TEST_COUNT];
	cpu_state target_out[OPT_FILTER_TEST_COUNT];
	u32 counterexample_count; // needed for the round robin test retire
	// output
	program best;
	// stats
	u64 total_candidates = 0;
	u64 filter_passes = 0;
	u64 smt_calls = 0;
	f64 ms_enum = 0.0;
	f64 ms_filter = 0.0;
	f64 ms_smt = 0.0;
	f64 ms_total = 0.0;
};
} // namespace sup
#endif // #ifndef OPT_OPTIMIZE_H
