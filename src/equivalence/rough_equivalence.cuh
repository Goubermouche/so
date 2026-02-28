#ifndef ROUGH_EQUIVALENCE_CUH
#define ROUGH_EQUIVALENCE_CUH

#include "emulator.cuh"

namespace so {
	using reg_mask = u32;

	__global__ void equivalence_ref_kernel(
		const inst* __restrict__ d_candidates,
		u32 num_candidates,
		u32 candidate_len,
		const cpu_state* __restrict__ d_test_inputs,
		const cpu_state* __restrict__ d_ref_outputs,
		u32 num_tests,
		reg_mask live_out,
		i32* __restrict__ d_result
	) {
		u32 idx = blockIdx.x * blockDim.x + threadIdx.x;

		if(idx >= num_candidates) {
			return;
		}

		if(*d_result < static_cast<i32>(num_candidates)) {
			return;
		}

		const inst* prog = d_candidates + idx * candidate_len;

		for(u32 t = 0; t < num_tests; ++t) {
			cpu_state state = d_test_inputs[t];
			run_program(prog, candidate_len, state);

			// check all live-out regs
			reg_mask mask = live_out;

			while(mask) {
				u32 r = __ffs(mask) - 1; // find first set bit (1-indexed)

				if(state.regs[r] != d_ref_outputs[t].regs[r]) {
					return;
				}

				mask &= mask - 1; // clear lowest bit
			}
		}

		atomicMin(d_result, (i32)idx);
	}

	void generate_test_inputs(cpu_state* out, u32 count, reg_mask live_in) {
		u64 seed = 0xDEADBEEFCAFEull;

		for(u32 i = 0; i < count; ++i) {
			for(u32 r = 0; r < REG_COUNT; ++r) {
				if(live_in & (1u << r)) {
					seed = seed * 6364136223846793005ull + 1442695040888963407ull;
					out[i].regs[r] = (u32)(seed >> 16);
				}
				else {
					out[i].regs[r] = 0; // dead
				}
			}
		}

		// corner cases
		if(count > 0) { for(u32 r = 0; r < REG_COUNT; ++r) if(live_in & (1u << r)) { out[0].regs[r] = 0; } }
		if(count > 1) { for(u32 r = 0; r < REG_COUNT; ++r) if(live_in & (1u << r)) { out[1].regs[r] = 0xFFFFFFFF; } }
		if(count > 2) { for(u32 r = 0; r < REG_COUNT; ++r) if(live_in & (1u << r)) { out[2].regs[r] = (r == 0) ? 1 : 0; } }
		if(count > 3) { for(u32 r = 0; r < REG_COUNT; ++r) if(live_in & (1u << r)) { out[3].regs[r] = (r == 0) ? 0x80000000 : 0; } }
	}
} // namespace so

#endif // #ifndef ROUGH_EQUIVALENCE_CUH
