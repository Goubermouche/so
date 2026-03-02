#ifndef ROUGH_EQUIVALENCE_CUH
#define ROUGH_EQUIVALENCE_CUH

#include "emulator.cuh"

namespace so {
	using reg_mask = u32;

	__global__ void search_kernel(
		const inst* __restrict__ inst_table,
		u32 inst_table_size,
		u32 prog_len,
		u64 total_programs,
		const cpu_state* __restrict__ test_inputs,
		const cpu_state* __restrict__ ref_outputs,
		u32 num_tests,
		reg_mask live_out,
		u64* __restrict__ result
	) {
		u64 idx = static_cast<u64>(blockIdx.x) * blockDim.x + threadIdx.x;

		if(idx >= total_programs) {
			return;
		}

		if(*result < total_programs) {
			return;
		}

		inst prog[MAX_PROG_LEN];
		u64 tmp = idx;

		for(u32 i = 0; i < prog_len; ++i) {
			prog[i] = inst_table[tmp % inst_table_size];
			tmp /= inst_table_size;
		}

		for(u32 t = 0; t < num_tests; ++t) {
			cpu_state state = test_inputs[t];

			for(u32 i = 0; i < prog_len; ++i) {
				execute_inst(state, prog[i]);
			}

			reg_mask mask = live_out;

			while(mask) {
				u32 r = __ffs(mask) - 1;

				if(state.regs[r] != ref_outputs[t].regs[r]) {
					return;
				}

				mask &= mask - 1;
			}
		}

		atomicMin(reinterpret_cast<unsigned long long*>(result), static_cast<unsigned long long>(idx));
	}

	void generate_test_inputs(cpu_state* out, u32 count, reg_mask live_in) {
		u64 seed = 0xDEADBEEFCAFEull;

		for(u32 i = 0; i < count; ++i) {
			for(u32 r = 0; r < REG_COUNT; ++r) {
				if(live_in & (1u << r)) {
					seed = seed * 6364136223846793005ull + 1442695040888963407ull;
					out[i].regs[r] = static_cast<u32>(seed >> 16);
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
