#ifndef OPT_DRIVER_CUH
#define OPT_DRIVER_CUH

#include "cpu/cpu.cuh"
#include "cpu/instruction.cuh"

#define OPT_PROGRAM_LEN 8
#define OPT_FILTER_TEST_COUNT 32
#define OPT_FILTER_WARPS_PER_BLOCK 4
#define OPT_FILTER_THREADS_PER_BLOCK OPT_FILTER_WARPS_PER_BLOCK * 32

typedef struct opt_filter_cfg {
	u64 live_mask;
	u32 prog_len;
	const cpu_inst* candidates;
	u64 n_candidates;
	const cpu_state* test_in;		 // reference inputs
	const cpu_state* target_out; // reference outputs
} opt_filter_cfg;

typedef struct opt_filter_ctx {
	u64 max_chunk_cands;
	// device
	void* d_cands;
	void* d_test_in;		// reference inputs
	void* d_target_out; // reference outputs
	void* d_pass_count; // per-candidate pass counts
} opt_filter_ctx;

typedef struct opt_shared_block {
	cpu_inst progs[OPT_FILTER_WARPS_PER_BLOCK][OPT_PROGRAM_LEN];
} opt_shared_block;

i32 opt_filter_make(opt_filter_ctx* ctx, u64 max_chunk_cands);
void opt_filter_free(opt_filter_ctx* ctx);
void opt_filter_run(opt_filter_ctx* ctx, opt_filter_cfg* cfg, u8* pass_counts);

#endif // #ifndef OPT_DRIVER_CUH
