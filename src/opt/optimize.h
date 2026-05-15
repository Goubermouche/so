#ifndef OPT_OPTIMIZE_H
#define OPT_OPTIMIZE_H

#include "cpu/program.h"
#include "opt/driver.cuh"
#include "opt/enumerate.cuh"
#include "smt/smt.h"

typedef struct opt_config {
	u64 live_mask;
	u64 seed;
	u32 ext_mask;
	u32 max_prog_len;
	u64 batch_size;
	u64 gpu_chunk_size;
	u32 max_cegis_iters;
} opt_config;

typedef struct opt_context {
	const cpu_program* prog;
	const opt_config* cfg;
	u64 live_in;
	u64 live_out;
	cpu_state test_in[SYNTH_N_TESTS];
	cpu_state target_out[SYNTH_N_TESTS];
	arena mem;
	cpu_inst* best_prog;
	u32 best_prog_len;
	u32 best_len;
	smt_verify_report rep;
	// stats
	u64 total_candidates;
	u64 total_gpu_passes;
	f64 total_gpu_ms;
	f64 total_smt_ms;
	u64 total_smt_calls;
	opt_gpu_context gpu;
	// persistent enumerator state: owns the device-side frontier ping-pong buffers and
	// the candidate output. allocated once at startup, reused across cegis iters
	opt_enum_context enum_ctx;
	u32 counterexample_count;
} opt_context;

typedef struct opt_survivor_set {
	u32_arr indices;
} opt_survivor_set;

opt_config opt_make_default_config();

void opt_print_reg_mask(u64 mask);
void opt_log_startup(const opt_context* ctx);
void opt_log_results(const opt_context* ctx, b32 found);

void opt_seed_test_vectors(opt_context* ctx);
void opt_filter_batch(opt_context* ctx, const opt_candidate* d_cands, u64 n_cands, u32 prog_len);
b32 opt_run_length(opt_context* ctx, u32 len);

void opt_run(const cpu_program* prog, const opt_config* cfg);

#endif // #ifndef OPT_OPTIMIZE_H
