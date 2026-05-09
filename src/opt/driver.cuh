#ifndef DRIVER_CUH
#define DRIVER_CUH

#include "int/cpu.cuh"
#include "int/instruction.cuh"

#define SYNTH_PROG_LEN 8
#define SYNTH_N_TESTS 64
#define N_WARPS_PER_BLOCK 4
#define THREADS_PER_BLOCK N_WARPS_PER_BLOCK * 32
#define TESTS_PER_LANE SYNTH_N_TESTS / 32

typedef struct opt_synth_config {
	u64 live_mask;
	u32 n_tests;
	u32 prog_len;
	const int_inst* candidates;
	u64 n_candidates;
	const int_cpu_state* test_in;
	const int_cpu_state* target_out;
	f64 elapsed_ms_total;
} opt_synth_config;

typedef struct opt_synth_result {
	u32 fail_mask;
	u32 pass_count;
} opt_synth_result;

typedef struct opt_gpu_context {
	u64 max_chunk_cands;
	void* d_cands;
	void* d_test_in;
	void* d_target_out;
	void* d_fail_mask;
	void* d_pass_count;
	void* h_fail_mask;
	void* h_pass_count;
} opt_gpu_context;

typedef struct opt_shared_block {
	int_inst progs[N_WARPS_PER_BLOCK][SYNTH_PROG_LEN];
} opt_shared_block;

i32 opt_gpu_runner_make(opt_gpu_context* ctx, u64 max_chunk_cands);
void opt_gpu_runner_free(opt_gpu_context* ctx);
void opt_gpu_runner_run(opt_gpu_context* ctx, opt_synth_config* cfg, opt_synth_result* results);

#endif // #ifndef DRIVER_CUH
