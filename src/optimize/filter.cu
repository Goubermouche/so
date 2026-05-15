#include "optimize/batch_runner.cuh"
#include "optimize/filter.cuh"

__global__ void opt_filter_kernel(const cpu_inst* __restrict__ cands,
																	const cpu_state* __restrict__ test_in,
																	const cpu_state* __restrict__ target_out,
																	u8* __restrict__ pass_count, u64 n_candidates,
																	u64 live_mask, u32 prog_len) {
	// go through candidate programs and run 32 quick tests to determine if a
	// given candidate COULD be equivalent to the reference program, one warp
	// runs one candidate (16 lanes => two passes for 32 tests)
	const u32 lane = threadIdx.x & 31;
	const u32 warp_local = threadIdx.x >> 5;
	const u64 cand_id = (u64)blockIdx.x * OPT_FILTER_WARPS_PER_BLOCK + warp_local;
	if(cand_id >= n_candidates) { return; }

	// init shared candidate block
	__shared__ opt_shared_block shared;
	if(lane < OPT_PROGRAM_LEN) {
		shared.progs[warp_local][lane] = cands[cand_id * OPT_PROGRAM_LEN + lane];
	}

	__syncwarp();

	const cpu_inst* prog = shared.progs[warp_local];
	u32 pass_local = 0;

	// phase 0: lanes 0-15 evaluate tests 0-15
	// phase 1: lanes 16-31 evaluate tests 16-31
#pragma unroll
	for(u32 phase = 0; phase < 2; ++phase) {
		const u32 phase_start = phase * 16;
		const u32 phase_end = phase_start + 16;
		const b32 in_phase = (lane >= phase_start) && (lane < phase_end);
		const b32 in_bounds = (lane < OPT_FILTER_TEST_COUNT);
		const b32 is_active = in_phase && in_bounds;
		b32 thread_failed = false;

		if(is_active) {
			u64 regs[32];
#pragma unroll
			// populate our registers with the test inputs
			for(u32 i = 0; i < 32; ++i) { regs[i] = test_in[lane].regs[i]; }
			// run test
			opt_lane_run(regs, prog, prog_len);

			b32 ok = true;
			u64 m = live_mask;
			// compare our results to the reference
			while(m) {
				const u32 r = __ffsll((long long)m) - 1;
				m &= m - 1;
				if(regs[r] != target_out[lane].regs[r]) {
					// mismatch => failed test
					ok = false;
					break;
				}
			}

			if(ok) {
				++pass_local;
			} else {
				thread_failed = true;
			}
		}

		// early out in phase 0
		if(__any_sync(0xFFFFFFFFu, thread_failed)) { break; }
	}

	// TODO: maybe there is a smarter scheme for determining a pass...
#pragma unroll
	for(int off = 16; off > 0; off >>= 1) {
		// warp-wide reduce to get pass count
		pass_local += __shfl_xor_sync(0xFFFFFFFFu, pass_local, off);
	}

	// pass results
	if(lane == 0) { pass_count[cand_id] = pass_local; }
}

i32 opt_filter_make(opt_filter_ctx* ctx, u64 max_chunk_cands) {
	ctx->max_chunk_cands = 0;
	ctx->d_cands = 0;
	ctx->d_test_in = 0;
	ctx->d_target_out = 0;
	ctx->d_pass_count = 0;
	i32 dev = 0;

	if(cudaGetDevice(&dev) != cudaSuccess) { return 1; }
	cudaDeviceProp p;
	if(cudaGetDeviceProperties(&p, dev) != cudaSuccess) { return 2; }
	u64 free_mem = 0;
	u64 total_mem = 0;
	if(cudaMemGetInfo(&free_mem, &total_mem) != cudaSuccess) { return 3; }
	u64 usable_mem = (u64)((f64)free_mem * 0.30);

	const u64 fixed_mem_bytes = 2ull * OPT_FILTER_TEST_COUNT * sizeof(cpu_state);
	if(usable_mem <= fixed_mem_bytes) {
		fprintf(stderr, "error: insufficient VRAM for fixed buffers\n");
		return 4;
	}

	usable_mem -= fixed_mem_bytes;
	const u64 per_cand_bytes = (u64)OPT_PROGRAM_LEN * sizeof(cpu_inst);
	const u64 cand_footprint_bytes = per_cand_bytes + sizeof(u32) + sizeof(u32);
	u64 chunk = usable_mem / cand_footprint_bytes;
	const u64 processor_count = p.multiProcessorCount;
	const u64 threads_per_processor = p.maxThreadsPerMultiProcessor;
	const u64 hw_warps = processor_count * threads_per_processor / 32ull;
	const u64 ideal_lower = hw_warps * 8ull;
	if(chunk < ideal_lower) { chunk = ideal_lower; }
	if(chunk < 1024) { chunk = 1024; }

	// cap the chunk size if max_chunk_cands is set
	if(max_chunk_cands != 0 && max_chunk_cands < chunk) {
		chunk = max_chunk_cands;
	}

	// align to warp block boundaries
	const u64 padded_chunk = chunk + OPT_FILTER_WARPS_PER_BLOCK - 1;
	const u64 num_blocks = padded_chunk / OPT_FILTER_WARPS_PER_BLOCK;
	chunk = num_blocks * OPT_FILTER_WARPS_PER_BLOCK;

	ctx->max_chunk_cands = chunk;

	// allocate persistent buffers
	const u64 cands_bytes = ctx->max_chunk_cands * per_cand_bytes;
	dmalloc(&ctx->d_cands, cands_bytes);
	dmalloc(&ctx->d_test_in, OPT_FILTER_TEST_COUNT * sizeof(cpu_state));
	dmalloc(&ctx->d_target_out, OPT_FILTER_TEST_COUNT * sizeof(cpu_state));
	dmalloc(&ctx->d_pass_count, ctx->max_chunk_cands * sizeof(u8));

	const u64 mask_bytes = ctx->max_chunk_cands * sizeof(u32) * 2;
	const u64 used_mem = cands_bytes + fixed_mem_bytes + mask_bytes;

	printf("filter:\n");
	printf("  chunk size: %zu cands\n", ctx->max_chunk_cands);
	printf("  VRAM: %zuMB / %zuMB avail\n", used_mem / MB(1), free_mem / MB(1));

	return 0;
}

void opt_filter_free(opt_filter_ctx* ctx) {
	if(ctx->d_cands) cudaFree(ctx->d_cands);
	if(ctx->d_test_in) cudaFree(ctx->d_test_in);
	if(ctx->d_target_out) cudaFree(ctx->d_target_out);
	if(ctx->d_pass_count) cudaFree(ctx->d_pass_count);
}

void opt_filter_run(opt_filter_ctx* ctx, opt_filter_cfg* cfg, u8* pass_counts) {
	if(cfg->candidates == 0) { return; }
	const u64 test_size = OPT_FILTER_TEST_COUNT * sizeof(cpu_state);

	// upload test vectors once
	htod_memcpy(ctx->d_test_in, cfg->test_in, test_size);
	htod_memcpy(ctx->d_target_out, cfg->target_out, test_size);
	u64 done = 0;

	// upload candidates as chunks so that we can process larger candidate sets
	// without running out of device memory
	while(done < cfg->n_candidates) {
		u64 this_chunk;

		if((cfg->n_candidates - done) < ctx->max_chunk_cands) {
			this_chunk = cfg->n_candidates - done;
		} else {
			this_chunk = ctx->max_chunk_cands;
		}

		const cpu_inst* d_chunk_cands = cfg->candidates + done * OPT_PROGRAM_LEN;
		const u32 total_warps = this_chunk + OPT_FILTER_WARPS_PER_BLOCK - 1;
		const u32 n_blocks = (u32)(total_warps / OPT_FILTER_WARPS_PER_BLOCK);
		dim3 grid(n_blocks);
		dim3 block(OPT_FILTER_THREADS_PER_BLOCK);

		// run chunk
		opt_filter_kernel<<<grid, block>>>(
			d_chunk_cands, (const cpu_state*)ctx->d_test_in,
			(const cpu_state*)ctx->d_target_out, (u8*)ctx->d_pass_count, this_chunk,
			cfg->live_mask, cfg->prog_len);
		check_cuda(cudaGetLastError(), "kernel launch");
		check_cuda(cudaDeviceSynchronize(), "kernel sync");

		// copy pass counts back to host
		dtoh_memcpy(pass_counts + done, ctx->d_pass_count, this_chunk * sizeof(u8));
		done += this_chunk;
	}
}