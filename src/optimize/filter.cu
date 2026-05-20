#include "optimize/filter.cuh"

namespace sup {
__global__ void opt_filter_kernel(const Instruction* __restrict__ cands,
																	const CpuState* __restrict__ test_in,
																	const CpuState* __restrict__ target_out,
																	u8* __restrict__ pass_count, u64 n_candidates,
																	u64 live_mask, u32 prog_len) {
	// go through candidate programs and run 32 quick tests to determine if a
	// given candidate COULD be equivalent to the reference program, one warp
	// runs one candidate (16 lanes => two passes for 32 tests)
	const u32 lane = threadIdx.x & 31;
	const u32 warp_local = threadIdx.x >> 5;
	const u64 cand_id = (u64)blockIdx.x * FilterWarpsPerBlock + warp_local;
	if(cand_id >= n_candidates) { return; }

	// init shared candidate block
	__shared__ FilterSharedBlock shared;
	if(lane < MaxProgramLen) {
		shared.progs[warp_local][lane] = cands[cand_id * MaxProgramLen + lane];
	}

	__syncwarp();

	const Instruction* prog = shared.progs[warp_local];
	u32 pass_local = 0;

	// phase 0: lanes 0-15 evaluate tests 0-15
	// phase 1: lanes 16-31 evaluate tests 16-31
#pragma unroll
	for(u32 phase = 0; phase < 2; ++phase) {
		const u32 phase_start = phase * 16;
		const u32 phase_end = phase_start + 16;
		const b32 in_phase = (lane >= phase_start) && (lane < phase_end);
		const b32 in_bounds = (lane < FilterTestCount);
		const b32 is_active = in_phase && in_bounds;
		b32 thread_failed = false;

		if(is_active) {
			u64 regs[32];
#pragma unroll
			// populate our registers with the test inputs
			for(u32 i = 0; i < 32; ++i) { regs[i] = test_in[lane].regs[i]; }
			// run test
			filter_run_lane(regs, prog, prog_len);

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

i32 filter_make(Filter* filter, u64 max_chunk_cands) {
	filter->max_chunk_cands = 0;
	filter->d_cands = 0;
	filter->d_test_in = 0;
	filter->d_target_out = 0;
	filter->d_pass_count = 0;
	i32 dev = 0;

	if(cudaGetDevice(&dev) != cudaSuccess) { return 1; }
	cudaDeviceProp p;
	if(cudaGetDeviceProperties(&p, dev) != cudaSuccess) { return 2; }
	u64 free_mem = 0;
	u64 total_mem = 0;
	if(cudaMemGetInfo(&free_mem, &total_mem) != cudaSuccess) { return 3; }
	u64 usable_mem = (u64)((f64)free_mem * 0.30);

	const u64 fixed_mem_bytes = 2ull * FilterTestCount * sizeof(CpuState);
	if(usable_mem <= fixed_mem_bytes) {
		fprintf(stderr, "error: insufficient VRAM for fixed buffers\n");
		return 4;
	}

	usable_mem -= fixed_mem_bytes;
	const u64 per_cand_bytes = (u64)MaxProgramLen * sizeof(Instruction);
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
	const u64 padded_chunk = chunk + FilterWarpsPerBlock - 1;
	const u64 num_blocks = padded_chunk / FilterWarpsPerBlock;
	chunk = num_blocks * FilterWarpsPerBlock;

	filter->max_chunk_cands = chunk;

	// allocate persistent buffers
	const u64 cands_bytes = filter->max_chunk_cands * per_cand_bytes;
	dmalloc(&filter->d_cands, cands_bytes);
	dmalloc(&filter->d_test_in, FilterTestCount * sizeof(CpuState));
	dmalloc(&filter->d_target_out, FilterTestCount * sizeof(CpuState));
	dmalloc(&filter->d_pass_count, filter->max_chunk_cands * sizeof(u8));

	const u64 mask_bytes = filter->max_chunk_cands * sizeof(u32) * 2;
	const u64 used_mem = cands_bytes + fixed_mem_bytes + mask_bytes;

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
}

void filter_run(Filter* filter, FilterOptions* opt, u8* pass_counts) {
	if(opt->candidates == 0) { return; }
	const u64 test_size = FilterTestCount * sizeof(CpuState);

	// upload test vectors once
	htod_memcpy(filter->d_test_in, opt->test_in, test_size);
	htod_memcpy(filter->d_target_out, opt->target_out, test_size);
	u64 done = 0;

	// upload candidates as chunks so that we can process larger candidate sets
	// without running out of device memory
	while(done < opt->n_candidates) {
		u64 this_chunk;

		if((opt->n_candidates - done) < filter->max_chunk_cands) {
			this_chunk = opt->n_candidates - done;
		} else {
			this_chunk = filter->max_chunk_cands;
		}

		const Instruction* d_chunk_cands = opt->candidates + done * MaxProgramLen;
		const u32 total_warps = this_chunk + FilterWarpsPerBlock - 1;
		const u32 n_blocks = (u32)(total_warps / FilterWarpsPerBlock);
		dim3 grid(n_blocks);
		dim3 block(FilterThreadsPerBlock);

		// run chunk
		opt_filter_kernel<<<grid, block>>>(
			d_chunk_cands, (const CpuState*)filter->d_test_in,
			(const CpuState*)filter->d_target_out, (u8*)filter->d_pass_count,
			this_chunk, opt->live_mask, opt->prog_len);
		check_cuda(cudaGetLastError(), "kernel launch");
		check_cuda(cudaDeviceSynchronize(), "kernel sync");

		// copy pass counts back to host
		dtoh_memcpy(pass_counts + done, filter->d_pass_count, this_chunk * sizeof(u8));
		done += this_chunk;
	}
}
} // namespace sup