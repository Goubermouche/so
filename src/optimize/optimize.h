#ifndef OPT_OPTIMIZE_H
#define OPT_OPTIMIZE_H

#include "cpu/program.h"
#include "optimize/enumerate.cuh"
#include "optimize/filter.cuh"

namespace sup {
typedef struct OptimizerOptions {
	u64 seed;
	u32 ext_mask;
	u64 batch_size;
	u32 max_cegis_iters;
} OptimizerOptions;

typedef struct Optimizer {
	const program* prog;
	const OptimizerOptions* opt;
	arena mem; // NOTE: maybe not really worth it here
	// input
	u64 live_in;
	u64 live_out;
	// pass contexts
	Enum enumerate;
	// filter
	Filter filter;
	CpuState test_in[FilterTestCount];
	CpuState target_out[FilterTestCount];
	u32 counterexample_count; // needed for the round robin test retire
	// output
	program best;
	// stats
	u64 total_candidates;
	u64 filter_passes;
	u64 smt_calls;
	f64 ms_enum;
	f64 ms_filter;
	f64 ms_smt;
	f64 ms_total;
} Optimize;

void optimizer_make_default_options(OptimizerOptions* opt);
i32  optimizer_make(Optimizer* optimizer, OptimizerOptions* opt);
void optimizer_free(Optimizer* optimizer);

i32  optimizer_run(Optimizer* optimizer, const program* program);
b32  optimizer_run_length(Optimizer* optimizer, u32 len);
b32  optimizer_filter_batch(Optimizer* optimizer, const EnumProgram* p, u64 p_cnt, u32 len);
void optimizer_init_tests(Optimizer* optimizer);

void optimizer_log_startup(Optimizer* optimizer);
void optimizer_log_results(Optimizer* optimizer, b32 found);
void optimizer_log_stats(Optimizer* optimizer);

} // namespace sup
#endif // #ifndef OPT_OPTIMIZE_H
