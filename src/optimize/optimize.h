#ifndef OPT_OPTIMIZE_H
#define OPT_OPTIMIZE_H

#include "cpu/program.h"
#include "optimize/filter.cuh"
#include "optimize/enumerate.cuh"
#include "smt/smt.h"

typedef struct opt_cfg {
	u64 seed;
	u32 ext_mask;
	u64 batch_size;
	u32 max_cegis_iters;
} opt_cfg;

typedef struct opt_ctx {
	arena mem; // NOTE: maybe not really worth it here
	// input
	const cpu_program* prog;
	const opt_cfg* cfg;
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
	cpu_program best;
	// stats
	u64 total_candidates;
	u64 filter_passes;
	u64 smt_calls;
	f64 ms_enum;
	f64 ms_filter;
	f64 ms_smt;
	f64 ms_total;
} opt_ctx;

opt_cfg opt_cfg_make_default();

void opt_print_reg_mask(u64 mask);
void opt_log_startup(const opt_ctx* ctx);
void opt_log_results(opt_ctx* ctx, b32 found);
void opt_log_stats(const opt_ctx* ctx);

u64 opt_compute_live_in(const cpu_program* program);
void opt_init_tests(opt_ctx* ctx);
b32 opt_filter_batch(opt_ctx* ctx, const opt_program* p, u64 p_cnt, u32 len);
b32 opt_run_length(opt_ctx* ctx, u32 len);

void opt_run(const cpu_program* prog, const opt_cfg* cfg);

#endif // #ifndef OPT_OPTIMIZE_H
