#include "opt/batch_runner.cuh"
#include "opt/driver.cuh"

__global__ void synth_kernel(const inst* __restrict__ d_cands, u64 n_candidates,
														 const cpu_state* __restrict__ d_test_in,
														 const cpu_state* __restrict__ d_target_out, u64 live_mask,
														 u32 prog_len, u32 n_tests, u32* __restrict__ d_fail_mask,
														 u32* __restrict__ d_pass_count) {
	const u32 lane = threadIdx.x & 31;
	const u32 warp_local = threadIdx.x >> 5;
	const u64 cand_id = (u64)blockIdx.x * N_WARPS_PER_BLOCK + warp_local;

	if(cand_id >= n_candidates) { return; }

	__shared__ opt_shared_block shared;

	if(lane == 0) {
#pragma unroll
		for(u32 i = 0; i < SYNTH_PROG_LEN; ++i) {
			shared.progs[warp_local][i] = d_cands[cand_id * SYNTH_PROG_LEN + i];
		}
	}

	__syncwarp();

	const inst* prog = shared.progs[warp_local];

	u32 fail_local = 0;
	u32 pass_local = 0;

#pragma unroll
	for(u32 t = 0; t < TESTS_PER_LANE; ++t) {
		const u32 test_idx = lane * TESTS_PER_LANE + t;

		if(test_idx >= n_tests) { break; }

		u64 regs[32];
#pragma unroll
		for(u32 i = 0; i < 32; ++i) { regs[i] = d_test_in[test_idx].regs[i]; }

		opt_lane_run(regs, prog, prog_len);

		b32 ok = true;
		u64 m = live_mask;
		while(m) {
			const u32 r = __ffsll((long long)m) - 1;
			m &= m - 1;
			if(regs[r] != d_target_out[test_idx].regs[r]) {
				ok = false;
				break;
			}
		}

		if(ok) {
			++pass_local;
		} else {
			fail_local |= (1u << test_idx);
		}
	}

// warp-wide reductions
#pragma unroll
	for(int off = 16; off > 0; off >>= 1) {
		fail_local |= __shfl_xor_sync(0xFFFFFFFFu, fail_local, off);
		pass_local += __shfl_xor_sync(0xFFFFFFFFu, pass_local, off);
	}

	if(lane == 0) {
		d_fail_mask[cand_id] = fail_local;
		d_pass_count[cand_id] = pass_local;
	}
}

i32 opt_gpu_runner_make(opt_gpu_context* ctx, u64 max_chunk_cands) {
	ctx->max_chunk_cands = 0;
	ctx->d_cands = 0;
	ctx->d_test_in = 0;
	ctx->d_target_out = 0;
	ctx->d_fail_mask = 0;
	ctx->d_pass_count = 0;
	ctx->h_fail_mask = 0;
	ctx->h_pass_count = 0;
	i32 dev = 0;

	if(cudaGetDevice(&dev) != cudaSuccess) { return 1; }
	cudaDeviceProp p;
	if(cudaGetDeviceProperties(&p, dev) != cudaSuccess) { return 2; }

	const u64 hw_warps = (u64)p.multiProcessorCount * (u64)p.maxThreadsPerMultiProcessor / 32ULL;
	const u64 ideal_lower = hw_warps * 8ull;
	const u64 mem_budget_bytes = 256ull * 1024ull * 1024ull;
	const u64 per_cand_bytes = (u64)SYNTH_PROG_LEN * sizeof(inst);
	const u64 mem_upper = mem_budget_bytes / per_cand_bytes;

	u64 chunk = ideal_lower;
	if(chunk < 1024) { chunk = 1024; }
	if(chunk > mem_upper) { chunk = mem_upper; }

	chunk = ((chunk + N_WARPS_PER_BLOCK - 1) / N_WARPS_PER_BLOCK) * N_WARPS_PER_BLOCK;

	if(max_chunk_cands != 0 && max_chunk_cands < chunk) {
		chunk = ((max_chunk_cands + N_WARPS_PER_BLOCK - 1) / N_WARPS_PER_BLOCK) * N_WARPS_PER_BLOCK;
	}

	ctx->max_chunk_cands = chunk;

	// allocate persistent buffers
	const u64 cands_bytes = ctx->max_chunk_cands * per_cand_bytes;
	dmalloc(&ctx->d_cands, cands_bytes, "alloc d_cands");
	dmalloc(&ctx->d_test_in, SYNTH_N_TESTS * sizeof(cpu_state), "alloc d_test_in");
	dmalloc(&ctx->d_target_out, SYNTH_N_TESTS * sizeof(cpu_state), "alloc d_target_out");
	dmalloc(&ctx->d_fail_mask, ctx->max_chunk_cands * sizeof(u32), "alloc d_fail_mask");
	dmalloc(&ctx->d_pass_count, ctx->max_chunk_cands * sizeof(u32), "alloc d_pass_count");
	// pinned host staging for fast async copyback
	hmalloc(&ctx->h_fail_mask, ctx->max_chunk_cands * sizeof(u32), "alloc h_fail_mask");
	hmalloc(&ctx->h_pass_count, ctx->max_chunk_cands * sizeof(u32), "alloc h_pass_count");

	const u64 chunk_mb = cands_bytes / (1024 * 1024);
	printf("  chunk size = %zu candidates (%zuMB)\n", ctx->max_chunk_cands, chunk_mb);

	return 0;
}

void opt_gpu_runner_free(opt_gpu_context* ctx) {
	if(ctx->d_cands) cudaFree(ctx->d_cands);
	if(ctx->d_test_in) cudaFree(ctx->d_test_in);
	if(ctx->d_target_out) cudaFree(ctx->d_target_out);
	if(ctx->d_fail_mask) cudaFree(ctx->d_fail_mask);
	if(ctx->d_pass_count) cudaFree(ctx->d_pass_count);
	if(ctx->h_fail_mask) cudaFreeHost(ctx->h_fail_mask);
	if(ctx->h_pass_count) cudaFreeHost(ctx->h_pass_count);
}

void opt_gpu_runner_run(opt_gpu_context* ctx, opt_synth_config* cfg, opt_synth_result* results) {
	cfg->elapsed_ms_total = 0.0;
	if(cfg->candidates == 0) { return; }

	const u64 test_size = SYNTH_N_TESTS * sizeof(cpu_state);

	// upload test vectors once
	htod_memcpy(ctx->d_test_in, cfg->test_in, test_size, "cp test_in");
	htod_memcpy(ctx->d_target_out, cfg->target_out, test_size, "cp target_out");

	const u64 per_cand_bytes = (u64)SYNTH_PROG_LEN * sizeof(inst);

	cudaEvent_t e0;
	cudaEvent_t e1;
	cudaEventCreate(&e0);
	cudaEventCreate(&e1);

	u64 done = 0;

	while(done < cfg->n_candidates) {
		u64 this_chunk;

		if((cfg->n_candidates - done) < ctx->max_chunk_cands) {
			this_chunk = cfg->n_candidates - done;
		} else {
			this_chunk = ctx->max_chunk_cands;
		}

		// upload this chunk's candidates
		const inst* to_copy = cfg->candidates + done * SYNTH_PROG_LEN;
		htod_memcpy(ctx->d_cands, to_copy, this_chunk * per_cand_bytes, "cp chunk cands");
		const u32 n_blocks = (u32)((this_chunk + N_WARPS_PER_BLOCK - 1) / N_WARPS_PER_BLOCK);
		dim3 grid(n_blocks);
		dim3 block(THREADS_PER_BLOCK);

		// run chunk
		cudaEventRecord(e0);
		synth_kernel<<<grid, block>>>(
			(const inst*)ctx->d_cands, this_chunk, (const cpu_state*)ctx->d_test_in,
			(const cpu_state*)ctx->d_target_out, cfg->live_mask, cfg->prog_len, cfg->n_tests,
			(u32*)ctx->d_fail_mask, (u32*)ctx->d_pass_count);
		cudaEventRecord(e1);
		check_cuda(cudaGetLastError(), "kernel launch");
		check_cuda(cudaDeviceSynchronize(), "kernel sync");

		// store timing
		f32 ms = 0.0f;
		cudaEventElapsedTime(&ms, e0, e1);
		cfg->elapsed_ms_total += (f64)ms;

		// copyback into pinned staging
		dtoh_memcpy(ctx->h_fail_mask, ctx->d_fail_mask, this_chunk * sizeof(u32), "cpback fail");
		dtoh_memcpy(ctx->h_pass_count, ctx->d_pass_count, this_chunk * sizeof(u32), "cpback pass");

		for(u64 i = 0; i < this_chunk; ++i) {
			results[done + i].fail_mask = ((u32*)ctx->h_fail_mask)[i];
			results[done + i].pass_count = ((u32*)ctx->h_pass_count)[i];
		}

		done += this_chunk;
	}

	cudaEventDestroy(e0);
	cudaEventDestroy(e1);
}
