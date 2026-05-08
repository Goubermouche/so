#include "opt/driver.cuh"
#include "opt/batch_runner.cuh"

namespace sup {
	static constexpr u32 TESTS_PER_LANE = SYNTH_N_TESTS / 32; // 2

	struct shared_block {
		inst progs[N_WARPS_PER_BLOCK][SYNTH_PROG_LEN];
	};

	__global__ void synth_kernel(
		const inst*      __restrict__ d_cands,
		u64 n_candidates,
		const cpu_state* __restrict__ d_test_in,
		const cpu_state* __restrict__ d_target_out,
		u64 live_mask,
		u32 prog_len,
		u32 n_tests,
		u32* __restrict__ d_fail_mask,
		u32* __restrict__ d_pass_count)
	{
		const u32 lane = threadIdx.x & 31;
		const u32 warp_local = threadIdx.x >> 5;
		const u64 cand_id = (u64)blockIdx.x * N_WARPS_PER_BLOCK + warp_local;

		if(cand_id >= n_candidates) {
			return;
		}

		__shared__ shared_block S;

		if(lane == 0) {
			#pragma unroll
			for(u32 i = 0; i < SYNTH_PROG_LEN; ++i) {
				S.progs[warp_local][i] = d_cands[cand_id * SYNTH_PROG_LEN + i];
			}
		}

		__syncwarp();

		const inst* prog = S.progs[warp_local];

		u32 fail_local = 0;
		u32 pass_local = 0;

		#pragma unroll
		for(u32 t = 0; t < TESTS_PER_LANE; ++t) {
			const u32 test_idx = lane * TESTS_PER_LANE + t;

			if(test_idx >= n_tests) {
				break;
			}

			u64 regs[32];
			#pragma unroll
			for(u32 i = 0; i < 32; ++i) {
				regs[i] = d_test_in[test_idx].regs[i];
			}

			run_program_lane(regs, prog, prog_len);

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
			}
			else {
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
			d_fail_mask [cand_id] = fail_local;
			d_pass_count[cand_id] = pass_local;
		}
	}

	gpu_runner::gpu_runner() :
		m_max_chunk_cands(0),
		m_d_cands(nullptr),
		m_d_test_in(nullptr),
		m_d_target_out(nullptr),
		m_d_fail_mask(nullptr),
		m_d_pass_count(nullptr),
		m_h_fail_mask(nullptr),
		m_h_pass_count(nullptr)
	{}

	gpu_runner::~gpu_runner() {
		if(m_d_cands)      cudaFree(m_d_cands);
		if(m_d_test_in)    cudaFree(m_d_test_in);
		if(m_d_target_out) cudaFree(m_d_target_out);
		if(m_d_fail_mask)  cudaFree(m_d_fail_mask);
		if(m_d_pass_count) cudaFree(m_d_pass_count);
		if(m_h_fail_mask)  cudaFreeHost(m_h_fail_mask);
		if(m_h_pass_count) cudaFreeHost(m_h_pass_count);
	}

	i32 gpu_runner::init(u64 requested_max_chunk_cands) {
		i32 dev = 0;

		if(cudaGetDevice(&dev) != cudaSuccess) {
			return 1;
		}

		cudaDeviceProp p;

		if(cudaGetDeviceProperties(&p, dev) != cudaSuccess) {
			return 2;
		}

		const u64 hw_warps = (u64)p.multiProcessorCount * (u64)p.maxThreadsPerMultiProcessor / 32ULL;
		const u64 ideal_lower = hw_warps * 8ULL;
		const u64 mem_budget_bytes = 256ULL * 1024ULL * 1024ULL;
		const u64 per_cand_bytes = (u64)SYNTH_PROG_LEN * sizeof(inst);
		const u64 mem_upper = mem_budget_bytes / per_cand_bytes;

		u64 chunk = ideal_lower;
		if(chunk < 1024) {
			chunk = 1024;
		}

		if(chunk > mem_upper) {
			chunk = mem_upper;
		}

		chunk = ((chunk + N_WARPS_PER_BLOCK - 1) / N_WARPS_PER_BLOCK) * N_WARPS_PER_BLOCK;

		if(requested_max_chunk_cands != 0 && requested_max_chunk_cands < chunk) {
			chunk = ((requested_max_chunk_cands + N_WARPS_PER_BLOCK - 1) / N_WARPS_PER_BLOCK) * N_WARPS_PER_BLOCK;
		}

		m_max_chunk_cands = chunk;

		// allocate persistent buffers
		const u64 cands_bytes = m_max_chunk_cands * per_cand_bytes;
		check_cuda(cudaMalloc(&m_d_cands,          cands_bytes),                       "alloc d_cands");
		check_cuda(cudaMalloc(&m_d_test_in,        SYNTH_N_TESTS * sizeof(cpu_state)), "alloc d_test_in");
		check_cuda(cudaMalloc(&m_d_target_out,     SYNTH_N_TESTS * sizeof(cpu_state)), "alloc d_target_out");
		check_cuda(cudaMalloc(&m_d_fail_mask,      m_max_chunk_cands * sizeof(u32)),   "alloc d_fail_mask");
		check_cuda(cudaMalloc(&m_d_pass_count,     m_max_chunk_cands * sizeof(u32)),   "alloc d_pass_count");
		// pinned host staging for fast async copyback
		check_cuda(cudaMallocHost(&m_h_fail_mask,  m_max_chunk_cands * sizeof(u32)),   "alloc h_fail_mask");
		check_cuda(cudaMallocHost(&m_h_pass_count, m_max_chunk_cands * sizeof(u32)),   "alloc h_pass_count");

		print("  chunk size = {} candidates ({} MB)\n", m_max_chunk_cands, cands_bytes / (1024 * 1024));

		return 0;
	}

	void gpu_runner::run(
		const inst* candidates,
		u64 n_candidates,
		const cpu_state* test_in,
		const cpu_state* target_out,
		const synth_config& cfg,
		synth_result* results,
		f64* elapsed_ms_total)
	{
		if(elapsed_ms_total) {
			*elapsed_ms_total = 0.0;
		}

		if(n_candidates == 0) {
			return;
		}

		// upload test vectors once
		check_cuda(cudaMemcpy(m_d_test_in,    test_in,    SYNTH_N_TESTS * sizeof(cpu_state), cudaMemcpyHostToDevice), "cp test_in");
		check_cuda(cudaMemcpy(m_d_target_out, target_out, SYNTH_N_TESTS * sizeof(cpu_state), cudaMemcpyHostToDevice), "cp target_out");

		const u64 per_cand_bytes = (u64)SYNTH_PROG_LEN * sizeof(inst);

		cudaEvent_t e0;
		cudaEvent_t e1;
		cudaEventCreate(&e0); cudaEventCreate(&e1);

		u64 done = 0;
		while(done < n_candidates) {
			const u64 this_chunk = (n_candidates - done) < m_max_chunk_cands ? (n_candidates - done) : m_max_chunk_cands;

			// upload this chunk's candidates
			check_cuda(cudaMemcpy(m_d_cands, candidates + done * SYNTH_PROG_LEN, this_chunk * per_cand_bytes, cudaMemcpyHostToDevice), "cp chunk cands");

			const u32 n_blocks = (u32)((this_chunk + N_WARPS_PER_BLOCK - 1) / N_WARPS_PER_BLOCK);
			dim3 grid(n_blocks);
			dim3 block(THREADS_PER_BLOCK);

			cudaEventRecord(e0);
			synth_kernel<<<grid, block>>>(
				(const inst*)m_d_cands, this_chunk,
				(const cpu_state*)m_d_test_in,
				(const cpu_state*)m_d_target_out,
				cfg.live_mask, cfg.prog_len, cfg.n_tests,
				(u32*)m_d_fail_mask, (u32*)m_d_pass_count
			);
			cudaEventRecord(e1);
			check_cuda(cudaGetLastError(), "kernel launch");
			check_cuda(cudaDeviceSynchronize(), "kernel sync");

			f32 ms = 0.0f;
			cudaEventElapsedTime(&ms, e0, e1);

			if(elapsed_ms_total) {
				*elapsed_ms_total += (f64)ms;
			}

			// copyback into pinned staging
			check_cuda(cudaMemcpy(m_h_fail_mask,  m_d_fail_mask,  this_chunk * sizeof(u32), cudaMemcpyDeviceToHost), "cpback fail");
			check_cuda(cudaMemcpy(m_h_pass_count, m_d_pass_count, this_chunk * sizeof(u32), cudaMemcpyDeviceToHost), "cpback pass");

			for(u64 i = 0; i < this_chunk; ++i) {
				results[done + i].fail_mask  = ((u32*)m_h_fail_mask)[i];
				results[done + i].pass_count = ((u32*)m_h_pass_count)[i];
			}

			done += this_chunk;
		}

		cudaEventDestroy(e0); cudaEventDestroy(e1);
	}
} // namespace sup

