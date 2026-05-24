#include "optimize/filter.cuh"

__global__ void opt_filter_kernel(const Instruction* __restrict__ cands,
																	const CpuState* __restrict__ test_in,
																	const CpuState* __restrict__ target_out,
																	U8* __restrict__ pass_count, U64 n_candidates, U64 live_mask,
																	U32 prog_len) {
	const U32 lane = threadIdx.x & 31;
	const U32 warp_local = threadIdx.x >> 5;
	const U64 cand_id = (U64)blockIdx.x * FilterWarpsPerBlock + warp_local;
	if(cand_id >= n_candidates) { return; }

	// init shared candidate block
	__shared__ FilterSharedBlock shared;
	if(lane < MaxProgramLen) {
		shared.progs[warp_local][lane] = cands[cand_id * MaxProgramLen + lane];
	}

	__syncwarp();

	const Instruction* prog = shared.progs[warp_local];
	U32 pass_local = 0;

	// phase 0: lanes 0-15 evaluate tests 0-15
	// phase 1: lanes 16-31 evaluate tests 16-31
#pragma unroll
	for(U32 phase = 0; phase < 2; ++phase) {
		const U32 phase_start = phase * 16;
		const U32 phase_end = phase_start + 16;
		const B32 in_phase = (lane >= phase_start) && (lane < phase_end);
		const B32 in_bounds = (lane < FilterTestCount);
		const B32 is_active = in_phase && in_bounds;
		B32 thread_failed = false;

		if(is_active) {
			U64 regs[32];
#pragma unroll
			// populate our registers with the test inputs
			for(U32 i = 0; i < 32; ++i) { regs[i] = test_in[lane].regs[i]; }
			// run test
			filter_run_lane(regs, prog, prog_len);

			B32 ok = true;
			U64 m = live_mask;
			// compare our results to the reference
			while(m) {
				const U32 r = __ffsll((long long)m) - 1;
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

I32 filter_make(Filter* filter, U64 max_chunk_cands) {
	filter->max_chunk_cands = 0;
	filter->d_cands = 0;
	filter->d_test_in = 0;
	filter->d_target_out = 0;
	filter->d_pass_count = 0;
	filter->h_pass_count = 0;
	filter->h_pass_count_cap = 0;
	filter->tests_dirty = true;

	I32 dev = 0;

	if(cudaGetDevice(&dev) != cudaSuccess) { return 1; }
	cudaDeviceProp p;
	if(cudaGetDeviceProperties(&p, dev) != cudaSuccess) { return 2; }
	U64 free_mem = 0;
	U64 total_mem = 0;
	if(cudaMemGetInfo(&free_mem, &total_mem) != cudaSuccess) { return 3; }
	U64 usable_mem = (U64)((F64)free_mem * 0.30);

	const U64 fixed_mem_bytes = 2ull * FilterTestCount * sizeof(CpuState);
	if(usable_mem <= fixed_mem_bytes) {
		fprintf(stderr, "error: insufficient VRAM for fixed buffers\n");
		return 4;
	}

	usable_mem -= fixed_mem_bytes;
	const U64 per_cand_bytes = (U64)MaxProgramLen * sizeof(Instruction);
	const U64 cand_footprint_bytes = per_cand_bytes + sizeof(U32) + sizeof(U32);
	U64 chunk = usable_mem / cand_footprint_bytes;
	const U64 processor_count = p.multiProcessorCount;
	const U64 threads_per_processor = p.maxThreadsPerMultiProcessor;
	const U64 hw_warps = processor_count * threads_per_processor / 32ull;
	const U64 ideal_lower = hw_warps * 8ull;
	if(chunk < ideal_lower) { chunk = ideal_lower; }
	if(chunk < 1024) { chunk = 1024; }

	if(max_chunk_cands != 0 && max_chunk_cands < chunk) { chunk = max_chunk_cands; }

	// align to warp block boundaries
	const U64 padded_chunk = chunk + FilterWarpsPerBlock - 1;
	const U64 num_blocks = padded_chunk / FilterWarpsPerBlock;
	chunk = num_blocks * FilterWarpsPerBlock;

	filter->max_chunk_cands = chunk;

	// allocate persistent buffers
	const U64 cands_bytes = filter->max_chunk_cands * per_cand_bytes;
	dmalloc(&filter->d_cands, cands_bytes);
	dmalloc(&filter->d_test_in, FilterTestCount * sizeof(CpuState));
	dmalloc(&filter->d_target_out, FilterTestCount * sizeof(CpuState));
	dmalloc(&filter->d_pass_count, filter->max_chunk_cands * sizeof(U8));

	// pinned host buffer for pass_count copyback, reused across all chunks
	filter->h_pass_count_cap = filter->max_chunk_cands;
	if(cudaMallocHost((void**)&filter->h_pass_count, filter->h_pass_count_cap * sizeof(U8)) !=
		 cudaSuccess) {
		filter->h_pass_count = (U8*)malloc(filter->h_pass_count_cap * sizeof(U8));
		if(!filter->h_pass_count) { return 5; }
	}

	const U64 mask_bytes = filter->max_chunk_cands * sizeof(U32) * 2;
	const U64 used_mem = cands_bytes + fixed_mem_bytes + mask_bytes;

	printf("filter:\n");
	printf("  chunk size: %zu cands\n", filter->max_chunk_cands);
	printf("  VRAM: %zuMB / %zuMB avail\n", used_mem / MB(1), free_mem / MB(1));

	return 0;
}

void filter_free(Filter* filter) {
	if(filter->d_cands) cudaFree(filter->d_cands);
	if(filter->d_test_in) cudaFree(filter->d_test_in);
	if(filter->d_target_out) cudaFree(filter->d_target_out);
	if(filter->d_pass_count) cudaFree(filter->d_pass_count);
	if(filter->h_pass_count) {
		if(cudaFreeHost(filter->h_pass_count) != cudaSuccess) { free(filter->h_pass_count); }
	}
}

void filter_mark_tests_dirty(Filter* filter) { filter->tests_dirty = true; }

void filter_run(Filter* filter, FilterOptions* opt, U8** out_pass_counts) {
	*out_pass_counts = filter->h_pass_count;
	if(opt->candidates == 0 || opt->n_candidates == 0) { return; }

	if(filter->tests_dirty) {
		const U64 test_size = FilterTestCount * sizeof(CpuState);
		htod_memcpy(filter->d_test_in, opt->test_in, test_size);
		htod_memcpy(filter->d_target_out, opt->target_out, test_size);
		filter->tests_dirty = false;
	}

	U64 done = 0;

	// upload candidates as chunks so that we can process larger candidate sets
	// without running out of device memory
	while(done < opt->n_candidates) {
		U64 this_chunk;

		if((opt->n_candidates - done) < filter->max_chunk_cands) {
			this_chunk = opt->n_candidates - done;
		} else {
			this_chunk = filter->max_chunk_cands;
		}

		const Instruction* d_chunk_cands = opt->candidates + done * MaxProgramLen;
		const U32 total_warps = this_chunk + FilterWarpsPerBlock - 1;
		const U32 n_blocks = (U32)(total_warps / FilterWarpsPerBlock);
		dim3 grid(n_blocks);
		dim3 block(FilterThreadsPerBlock);

		// run chunk
		opt_filter_kernel<<<grid, block>>>(
			d_chunk_cands, (const CpuState*)filter->d_test_in, (const CpuState*)filter->d_target_out,
			(U8*)filter->d_pass_count, this_chunk, opt->live_mask, opt->prog_len);
		check_cuda(cudaGetLastError(), "kernel launch");
		dtoh_memcpy(filter->h_pass_count + done, filter->d_pass_count, this_chunk * sizeof(U8));
		done += this_chunk;
	}
}
