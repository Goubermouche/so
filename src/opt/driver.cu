#include "opt/driver.cuh"
#include "opt/batch_runner.cuh"
#include "opt/mutate.cuh"
#include "opt/bloom.cuh"
#include "opt/canon.cuh"
#include "opt/cost.cuh"

namespace sup {
	struct warp_state {
		inst current[MCMC_PROG_LEN];
		inst candidate[MCMC_PROG_LEN];
		inst best[MCMC_PROG_LEN];
		rng chain_rng;
		u32 current_correct;
		u32 current_perf;
		u32 current_cost;
		u32 best_cost;
		u32 best_correct;
		u32 best_perf;
		u64 accepted;
		u64 skipped_bloom;
	};

	__device__ __forceinline__ u32 warp_reduce_sum_u32(u32 v) {
		#pragma unroll
		for(int offset = 16; offset > 0; offset >>= 1) {
			v += __shfl_xor_sync(0xFFFFFFFFu, v, offset);
		}

		return v;
	}

	__global__ void mcmc_kernel(
		const cpu_state* __restrict__ d_test_in,
		const cpu_state* __restrict__ d_target_out,
		const u32* __restrict__ d_test_weights,
		const u64* __restrict__ d_seeds,
		const inst* __restrict__ d_seed_prog,
		u32 seed_prog_len,
		u64 preserved_mask,
		u64 live_mask,
		u32 perf_weight,
		u32 correct_weight,
		f32 beta,
		u64 max_steps,
		u32 n_chains,
		u32* __restrict__ d_bloom,
		u32 bloom_block_mask,
		// outputs:
		inst* __restrict__ d_best_progs,
		u32* __restrict__ d_best_costs,
		u32* __restrict__ d_best_correct,
		u32* __restrict__ d_best_perf,
		u64* __restrict__ d_accepted,
		u64* __restrict__ d_skipped_bloom
	) {
		// identity
		const u32 lane = threadIdx.x & 31;
		const u32 warp_local = threadIdx.x >> 5;
		const u32 chain_id = blockIdx.x * N_WARPS_PER_BLOCK + warp_local;

		if(chain_id >= n_chains) {
			return;
		}

		__shared__ warp_state ws[N_WARPS_PER_BLOCK];
		warp_state& W = ws[warp_local];
		u64 test_in_regs[16];
		u64 target_regs[16];

		#pragma unroll
		for(int i = 0; i < 16; ++i) {
			test_in_regs[i] = d_test_in[lane].regs[i];
			target_regs[i]  = d_target_out[lane].regs[i];
		}

		const u32 test_weight = d_test_weights[lane];

		// ;ane 0 initializes the chain
		if(lane == 0) {
			W.chain_rng.s = d_seeds[chain_id];

			if(d_seed_prog) {
				for(u32 i = 0; i < MCMC_PROG_LEN; ++i) {
					if(i < seed_prog_len) {
						W.current[i] = d_seed_prog[i];
					}
					else {
						W.current[i].op = OP_NOP;

						for(u32 k = 0; k < 4; ++k) {
							W.current[i].operands[k].i = 0;
						}
					}
				}
			}
			else {
				for(u32 i = 0; i < MCMC_PROG_LEN; ++i) {
					W.current[i] = random_inst(&W.chain_rng);
				}
			}

			canonicalize(W.current, MCMC_PROG_LEN, preserved_mask);
			W.accepted = 0;
			W.skipped_bloom = 0;
		}

		__syncwarp();

		// evaluate the initial program
		u64 regs[16];

		#pragma unroll
		for(int i = 0; i < 16; ++i) {
			regs[i] = test_in_regs[i];
		}

		run_program_lane(regs, W.current, MCMC_PROG_LEN);
		u32 local_correct = 0;

		{
			u64 m = live_mask;
			while(m) {
				const u32 r = __ffsll((long long)m) - 1;
				m &= m - 1;
				local_correct += __popcll(regs[r] ^ target_regs[r]);
			}
		}

		// per-test weight
		local_correct *= test_weight;
		u32 total_correct = warp_reduce_sum_u32(local_correct);

		if(lane == 0) {
			W.current_correct = total_correct;
			W.current_perf = perf_cost(W.current, MCMC_PROG_LEN, live_mask);
			W.current_cost = correct_weight * W.current_correct + perf_weight * W.current_perf;

			for(u32 i = 0; i < MCMC_PROG_LEN; ++i) {
				W.best[i] = W.current[i];
			}

			W.best_cost = W.current_cost;
			W.best_correct = W.current_correct;
			W.best_perf = W.current_perf;
		}

		__syncwarp();

		// main loop
		for(u64 step = 0; step < max_steps; ++step) {
			// lane 0 proposes, computes new_perf, and samples the acceptance threshold up front
			u32 new_perf = 0;
			i32 correct_thresh = 0;

			if(lane == 0) {
				for(u32 i = 0; i < MCMC_PROG_LEN; ++i) {
					W.candidate[i] = W.current[i];
				}

				mutate_one(W.candidate, MCMC_PROG_LEN, &W.chain_rng);
				canonicalize(W.candidate, MCMC_PROG_LEN, preserved_mask);

				new_perf = perf_cost(W.candidate, MCMC_PROG_LEN, live_mask);

				const f32 p = rng_unit(&W.chain_rng);
				const f32 p_safe = p > 1e-30f ? p : 1e-30f;
				const f32 budget_f = (f32)W.current_cost - __logf(p_safe) / beta;
				const f32 thresh_f = (budget_f - (f32)(perf_weight * new_perf)) / (f32)correct_weight;
				correct_thresh = (thresh_f < 0.0f) ? -1 : (i32)thresh_f;
			}

			__syncwarp();

			// broadcast new_perf + correct_thresh from lane 0 to the warp
			new_perf = __shfl_sync(0xFFFFFFFFu, new_perf, 0);
			correct_thresh = __shfl_sync(0xFFFFFFFFu, correct_thresh, 0);

			// too expensive due to perf
			if(correct_thresh < 0) {
				__syncwarp();
				continue;
			}

			// bloom filter reject
			if(d_bloom) {
				u32 bloom_hit_i = 0;

				if(lane == 0) {
					const u64 h = hash_program64(W.candidate, MCMC_PROG_LEN);
					bloom_hit_i = bloom_check_and_insert(d_bloom, bloom_block_mask, h) ? 1u : 0u;
				}

				bloom_hit_i = __shfl_sync(0xFFFFFFFFu, bloom_hit_i, 0);

				if(bloom_hit_i) {
					if(lane == 0) ++W.skipped_bloom;
					__syncwarp();
					continue;
				}
			}

			// interpret the candidate and sum correctness.
			#pragma unroll
			for(int i = 0; i < 16; ++i) {
				regs[i] = test_in_regs[i];
			}

			run_program_lane(regs, W.candidate, MCMC_PROG_LEN);
			local_correct = 0;

			{
				u64 m = live_mask;
				while(m) {
					const u32 r = __ffsll((long long)m) - 1;
					m &= m - 1;
					local_correct += __popcll(regs[r] ^ target_regs[r]);
				}
			}

			local_correct *= test_weight;
			total_correct = warp_reduce_sum_u32(local_correct);

			// correctness exceeds threshold - reject without running mh
			if((i32)total_correct > correct_thresh) {
				__syncwarp();
				continue;
			}

			// accept
			const u32 new_cost = correct_weight * total_correct + perf_weight * new_perf;

			if(lane == 0) {
				for(u32 i = 0; i < MCMC_PROG_LEN; ++i) {
					W.current[i] = W.candidate[i];
				}

				W.current_correct = total_correct;
				W.current_perf = new_perf;
				W.current_cost = new_cost;
				++W.accepted;

				if(new_cost < W.best_cost) {
					for(u32 i = 0; i < MCMC_PROG_LEN; ++i) {
						W.best[i] = W.candidate[i];
					}

					W.best_cost = new_cost;
					W.best_correct = total_correct;
					W.best_perf = new_perf;
				}
			}

			__syncwarp();
		}

		// write current best result to global memory.
		if(lane == 0) {
			for(u32 i = 0; i < MCMC_PROG_LEN; ++i) {
				d_best_progs[chain_id * MCMC_PROG_LEN + i] = W.best[i];
			}

			d_best_costs[chain_id] = W.best_cost;
			d_best_correct[chain_id] = W.best_correct;
			d_best_perf[chain_id] = W.best_perf;
			d_accepted[chain_id] = W.accepted;
			d_skipped_bloom[chain_id] = W.skipped_bloom;
		}
	}

	mcmc_result* mcmc_run_gpu(
		const inst* target_prog,
		u32 target_len,
		const cpu_state* test_in,
		const mcmc_config& cfg
	) {
		// compute target outputs, live-in, preserved mask, seeds
		cpu_state target_out[MCMC_N_TESTS];

		for(u32 s = 0; s < MCMC_N_TESTS; ++s) {
			u64 regs[16];

			for(u32 i = 0; i < 16; ++i) {
				regs[i] = test_in[s].regs[i];
			}

			run_program_lane(regs, target_prog, target_len);

			for(u32 i = 0; i < 16; ++i) {
				target_out[s].regs[i] = regs[i];
			}
		}

		const u64 live_in = compute_live_in(target_prog, target_len);
		const u64 preserved = cfg.live_mask | live_in;

		// per-chain seeds
		const u32 n_chains = cfg.n_chains;
		u64* h_seeds = (u64*)malloc(n_chains * sizeof(u64));

		{
			u64 s = cfg.master_seed ? cfg.master_seed : 0xCAFEBABEDEADBEEFULL;

			for(u32 i = 0; i < n_chains; ++i) {
				s ^= s >> 30; s *= 0xBF58476D1CE4E5B9ULL;
				s ^= s >> 27; s *= 0x94D049BB133111EBULL;
				s ^= s >> 31;
				h_seeds[i] = s ? s : 1;
			}
		}

		// allocate buffers
		cpu_state* d_test_in;       check_cuda(cudaMalloc(&d_test_in,       MCMC_N_TESTS * sizeof(cpu_state)),        "alloc test_in");
		cpu_state* d_target_out;    check_cuda(cudaMalloc(&d_target_out,    MCMC_N_TESTS * sizeof(cpu_state)),        "alloc target_out");
		u32*       d_test_weights;  check_cuda(cudaMalloc(&d_test_weights,  MCMC_N_TESTS * sizeof(u32)),              "alloc test_weights");
		u64*       d_seeds;         check_cuda(cudaMalloc(&d_seeds,         n_chains     * sizeof(u64)),              "alloc seeds");
		inst*      d_best_progs;    check_cuda(cudaMalloc(&d_best_progs,    n_chains * MCMC_PROG_LEN * sizeof(inst)), "alloc best_progs");
		u32*       d_best_costs;    check_cuda(cudaMalloc(&d_best_costs,    n_chains * sizeof(u32)),                  "alloc best_costs");
		u32*       d_best_correct;  check_cuda(cudaMalloc(&d_best_correct,  n_chains * sizeof(u32)),                  "alloc best_correct");
		u32*       d_best_perf;     check_cuda(cudaMalloc(&d_best_perf,     n_chains * sizeof(u32)),                  "alloc best_perf");
		u64*       d_accepted;      check_cuda(cudaMalloc(&d_accepted,      n_chains * sizeof(u64)),                  "alloc accepted");
		u64*       d_skipped_bloom; check_cuda(cudaMalloc(&d_skipped_bloom, n_chains * sizeof(u64)),                  "alloc skipped_bloom");

		// auto-size the bloom filter from the expected candidate count
		u32* d_bloom = nullptr;
		u32  bloom_n_blocks = 0;

		if(cfg.use_bloom) {
			const u64 expected_cands = (u64)n_chains * cfg.max_steps;
			bloom_n_blocks = bloom_n_blocks_for(expected_cands);
			const u64 bloom_bytes = (u64)bloom_n_blocks * BLOOM_BLOCK_WORDS * sizeof(u32);
			check_cuda(cudaMalloc(&d_bloom, bloom_bytes), "alloc bloom");
			check_cuda(cudaMemset(d_bloom, 0, bloom_bytes), "zero bloom");
		}

		// upload the seed program if the caller wants chains to start from the target
		inst* d_seed_prog = nullptr;
		u32 seed_prog_len = 0;

		if(cfg.seed_from_target) {
			const u32 n_copy = target_len > MCMC_PROG_LEN ? MCMC_PROG_LEN : target_len;

			if(target_len > MCMC_PROG_LEN) {
				print_err("warning: target_len={} exceeds MCMC_PROG_LEN={}; truncating\n", target_len, MCMC_PROG_LEN);
			}

			check_cuda(cudaMalloc(&d_seed_prog, MCMC_PROG_LEN * sizeof(inst)), "alloc seed_prog");
			check_cuda(cudaMemcpy(d_seed_prog, target_prog, n_copy * sizeof(inst), cudaMemcpyHostToDevice), "cp seed_prog");
			seed_prog_len = n_copy;
		}

		check_cuda(cudaMemcpy(d_test_in,    test_in,    MCMC_N_TESTS * sizeof(cpu_state), cudaMemcpyHostToDevice), "cp test_in");
		check_cuda(cudaMemcpy(d_target_out, target_out, MCMC_N_TESTS * sizeof(cpu_state), cudaMemcpyHostToDevice), "cp target_out");
		check_cuda(cudaMemcpy(d_seeds,      h_seeds,    n_chains * sizeof(u64),           cudaMemcpyHostToDevice), "cp seeds");

		// per-test weights
		u32 weights_h[MCMC_N_TESTS];

		for(u32 i = 0; i < MCMC_N_TESTS; ++i) {
			weights_h[i] = cfg.test_weights[i] ? cfg.test_weights[i] : 1u;
		}

		check_cuda(cudaMemcpy(d_test_weights, weights_h, MCMC_N_TESTS * sizeof(u32), cudaMemcpyHostToDevice), "cp test_weights");

		// launch
		const u32 n_blocks = (n_chains + N_WARPS_PER_BLOCK - 1) / N_WARPS_PER_BLOCK;
		dim3 grid(n_blocks);
		dim3 block(THREADS_PER_BLOCK);

		mcmc_kernel<<<grid, block>>>(
			d_test_in, d_target_out, d_test_weights, d_seeds,
			d_seed_prog, seed_prog_len,
			preserved, cfg.live_mask, cfg.perf_weight, cfg.correct_weight, cfg.beta, cfg.max_steps, n_chains,
			d_bloom, bloom_n_blocks ? bloom_n_blocks - 1 : 0,
			d_best_progs, d_best_costs, d_best_correct, d_best_perf, d_accepted, d_skipped_bloom
		);

		check_cuda(cudaGetLastError(), "kernel launch");
		check_cuda(cudaDeviceSynchronize(), "kernel sync");

		// copy results back, pack into mcmc_result[].
		inst* h_best_progs    = (inst*)malloc(n_chains * MCMC_PROG_LEN * sizeof(inst));
		u32*  h_best_costs    = (u32*) malloc(n_chains * sizeof(u32));
		u32*  h_best_correct  = (u32*) malloc(n_chains * sizeof(u32));
		u32*  h_best_perf     = (u32*) malloc(n_chains * sizeof(u32));
		u64*  h_accepted      = (u64*) malloc(n_chains * sizeof(u64));
		u64*  h_skipped_bloom = (u64*) malloc(n_chains * sizeof(u64));

		check_cuda(cudaMemcpy(h_best_progs,    d_best_progs,    n_chains * MCMC_PROG_LEN * sizeof(inst), cudaMemcpyDeviceToHost), "cpback progs");
		check_cuda(cudaMemcpy(h_best_costs,    d_best_costs,    n_chains * sizeof(u32), cudaMemcpyDeviceToHost), "cpback costs");
		check_cuda(cudaMemcpy(h_best_correct,  d_best_correct,  n_chains * sizeof(u32), cudaMemcpyDeviceToHost), "cpback correct");
		check_cuda(cudaMemcpy(h_best_perf,     d_best_perf,     n_chains * sizeof(u32), cudaMemcpyDeviceToHost), "cpback perf");
		check_cuda(cudaMemcpy(h_accepted,      d_accepted,      n_chains * sizeof(u64), cudaMemcpyDeviceToHost), "cpback accepted");
		check_cuda(cudaMemcpy(h_skipped_bloom, d_skipped_bloom, n_chains * sizeof(u64), cudaMemcpyDeviceToHost), "cpback skipped");

		mcmc_result* results = (mcmc_result*)malloc(n_chains * sizeof(mcmc_result));

		for(u32 c = 0; c < n_chains; ++c) {
			for(u32 i = 0; i < MCMC_PROG_LEN; ++i) {
				results[c].best_prog[i] = h_best_progs[c * MCMC_PROG_LEN + i];
			}

			results[c].best_cost        = h_best_costs[c];
			results[c].best_correctness = h_best_correct[c];
			results[c].best_perf        = h_best_perf[c];
			results[c].accepted         = h_accepted[c];
			results[c].skipped_bloom    = h_skipped_bloom[c];
		}

		free(h_best_progs);
		free(h_best_costs);
		free(h_best_correct);
		free(h_best_perf);
		free(h_accepted);
		free(h_skipped_bloom);
		free(h_seeds);

		cudaFree(d_test_in);
		cudaFree(d_target_out);
		cudaFree(d_test_weights);
		cudaFree(d_seeds);
		cudaFree(d_best_progs);
		cudaFree(d_best_costs);
		cudaFree(d_best_correct);
		cudaFree(d_best_perf);
		cudaFree(d_accepted);
		cudaFree(d_skipped_bloom);

		if(d_bloom) {
			cudaFree(d_bloom);
		}

		if(d_seed_prog) {
			cudaFree(d_seed_prog);
		}

		return results;
	}
} // namespace sup


