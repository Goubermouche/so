#ifndef OPT_OPTIMIZE_H
#define OPT_OPTIMIZE_H

#include "cpu/program.h"
#include "optimize/enumerate.cuh"
#include "optimize/filter.cuh"

typedef struct OptimizerOptions {
	U64 seed;
	U32 ext_mask;
	U64 batch_size;
	U32 max_cegis_iters;
} OptimizerOptions;

typedef struct Optimizer {
	Program* prog;
	OptimizerOptions* opt;
	Arena* mem; // NOTE: maybe not really worth it here
	// input
	U64 live_in;
	U64 live_out;
	// pass contexts
	Enum enumerate;
	// filter
	Filter filter;
	CpuState test_in[FilterTestCount];
	CpuState target_out[FilterTestCount];
	U32 counterexample_count; // needed for the round robin test retire
	// current pass context
	U32 cur_max_scratch;
	U64 cur_active_mask;
	EnumMeta cur_meta[EnumMaxMeta];
	U32 cur_n_meta;
	EnumImmPool cur_imms;
	// output
	Program best;
	// stats
	U64 total_candidates;
	U64 filter_passes;
	U64 smt_calls;
	F64 ms_enum;
	F64 ms_filter;
	F64 ms_smt;
	F64 ms_total;
} Optimize;

void optimizer_make_default_options(OptimizerOptions* opt);
I32 optimizer_make(Optimizer* optimizer, OptimizerOptions* opt);
void optimizer_free(Optimizer* optimizer);

I32 optimizer_run(Optimizer* optimizer, Program* Program);
B32 optimizer_run_length(Optimizer* optimizer, U32 len);
I32 optimizer_run_iter(Optimizer* optimizer, EnumOptions* cfg, U32 len, U32 iter);
B32 optimizer_filter_batch(Optimizer* optimizer, U32 len);
void optimizer_init_tests(Optimizer* optimizer);
void optimizer_reconstruct_survivor(Optimizer* optimizer, U64 i, U32 len, Instruction* out_inst);

void optimizer_log_startup(Optimizer* optimizer);
void optimizer_log_results(Optimizer* optimizer, B32 found);
void optimizer_log_stats(Optimizer* optimizer);
#endif // #ifndef OPT_OPTIMIZE_H
