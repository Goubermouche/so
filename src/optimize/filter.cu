#include "optimize/batch_runner.cuh"
#include "optimize/filter.cuh"

__global__ void synth_kernel(const cpu_inst* __restrict__ d_cands, u64 n_candidates,
														 const cpu_state* __restrict__ d_test_in,
														 const cpu_state* __restrict__ d_target_out, u64 live_mask,
														 u32 prog_len, u32* __restrict__ d_fail_mask,
														 u32* __restrict__ d_pass_count) {
	const u32 lane = threadIdx.x & 31;
	const u32 warp_local = threadIdx.x >> 5;
	const u64 cand_id = (u64)blockIdx.x * N_WARPS_PER_BLOCK + warp_local;

	if(cand_id >= n_candidates) { return; }

	__shared__ opt_shared_block shared;

	if(lane < SYNTH_PROG_LEN) {
		shared.progs[warp_local][lane] = d_cands[cand_id * SYNTH_PROG_LEN + lane];
	}

	__syncwarp();

	const cpu_inst* prog = shared.progs[warp_local];

	u32 fail_local = 0;
	u32 pass_local = 0;

	// phase 0: lanes 0-15 evaluate tests 0-15
	// phase 1: lanes 16-31 evaluate tests 16-31
#pragma unroll
	for(u32 phase = 0; phase < 2; ++phase) {
		const u32 phase_start = phase * 16;
		const u32 phase_end = phase_start + 16;
		const b32 in_phase = (lane >= phase_start) && (lane < phase_end);
		const b32 in_bounds = (lane < SYNTH_N_TESTS);
		const b32 is_active = in_phase && in_bounds;

		if(is_active) {
			u64 regs[32];
#pragma unroll
			for(u32 i = 0; i < 32; ++i) { regs[i] = d_test_in[lane].regs[i]; }

			opt_lane_run(regs, prog, prog_len);

			b32 ok = true;
			u64 m = live_mask;
			while(m) {
				const u32 r = __ffsll((long long)m) - 1;
				m &= m - 1;
				if(regs[r] != d_target_out[lane].regs[r]) {
					ok = false;
					break;
				}
			}

			if(ok) {
				++pass_local;
			} else {
				fail_local |= (1u << lane);
			}
		}

		// early out in phase 0
		if(__any_sync(0xFFFFFFFFu, fail_local)) { break; }
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

i32 opt_filter_make(opt_filter_ctx* ctx, u64 max_chunk_cands) {
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

	u64 free_mem = 0;
	u64 total_mem = 0;
	if(cudaMemGetInfo(&free_mem, &total_mem) != cudaSuccess) { return 3; }
	u64 usable_mem = (u64)((f64)free_mem * 0.30);

	const u64 fixed_mem_bytes = 2ull * SYNTH_N_TESTS * sizeof(cpu_state);
	if(usable_mem <= fixed_mem_bytes) {
		fprintf(stderr, "error: insufficient VRAM for fixed buffers\n");
		return 4;
	}

	usable_mem -= fixed_mem_bytes;

	const u64 per_cand_bytes = (u64)SYNTH_PROG_LEN * sizeof(cpu_inst);
	const u64 cand_footprint_bytes = per_cand_bytes + sizeof(u32) + sizeof(u32);
	u64 chunk = usable_mem / cand_footprint_bytes;
	const u64 hw_warps = (u64)p.multiProcessorCount * (u64)p.maxThreadsPerMultiProcessor / 32ULL;
	const u64 ideal_lower = hw_warps * 8ull;
	if(chunk < ideal_lower) { chunk = ideal_lower; }
	if(chunk < 1024) { chunk = 1024; }

	// align to warp block boundaries
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

	const u64 mask_bytes = ctx->max_chunk_cands * sizeof(u32) * 2;
	const u64 total_allocated_bytes = cands_bytes + fixed_mem_bytes + mask_bytes;

	printf("> chunk size: %zu candidates\n", ctx->max_chunk_cands);
	printf("> VRAM: %zuMB / %zuMB avail\n", total_allocated_bytes / MB(1), free_mem / MB(1));

	return 0;
}

void opt_filter_free(opt_filter_ctx* ctx) {
	if(ctx->d_cands) cudaFree(ctx->d_cands);
	if(ctx->d_test_in) cudaFree(ctx->d_test_in);
	if(ctx->d_target_out) cudaFree(ctx->d_target_out);
	if(ctx->d_fail_mask) cudaFree(ctx->d_fail_mask);
	if(ctx->d_pass_count) cudaFree(ctx->d_pass_count);
	if(ctx->h_fail_mask) cudaFreeHost(ctx->h_fail_mask);
	if(ctx->h_pass_count) cudaFreeHost(ctx->h_pass_count);
}

void opt_filter_run(opt_filter_ctx* ctx, opt_filter_config* cfg, opt_synth_result* results) {
	if(cfg->candidates == 0) { return; }

	const u64 test_size = SYNTH_N_TESTS * sizeof(cpu_state);

	// upload test vectors once
	htod_memcpy(ctx->d_test_in, cfg->test_in, test_size, "cp test_in");
	htod_memcpy(ctx->d_target_out, cfg->target_out, test_size, "cp target_out");

	const u64 per_cand_bytes = (u64)SYNTH_PROG_LEN * sizeof(cpu_inst);

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

		const cpu_inst* d_chunk_cands;
		if(cfg->candidates_on_device) {
			d_chunk_cands = cfg->candidates + done * SYNTH_PROG_LEN;
		} else {
			const cpu_inst* to_copy = cfg->candidates + done * SYNTH_PROG_LEN;
			htod_memcpy(ctx->d_cands, to_copy, this_chunk * per_cand_bytes, "cp chunk cands");
			d_chunk_cands = (const cpu_inst*)ctx->d_cands;
		}
		const u32 n_blocks = (u32)((this_chunk + N_WARPS_PER_BLOCK - 1) / N_WARPS_PER_BLOCK);
		dim3 grid(n_blocks);
		dim3 block(THREADS_PER_BLOCK);

		// run chunk
		cudaEventRecord(e0);
		synth_kernel<<<grid, block>>>(d_chunk_cands, this_chunk, (const cpu_state*)ctx->d_test_in,
																	(const cpu_state*)ctx->d_target_out, cfg->live_mask,
																	cfg->prog_len, (u32*)ctx->d_fail_mask, (u32*)ctx->d_pass_count);
		cudaEventRecord(e1);
		check_cuda(cudaGetLastError(), "kernel launch");
		check_cuda(cudaDeviceSynchronize(), "kernel sync");

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