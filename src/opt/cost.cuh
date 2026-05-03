#ifndef COST_CUH
#define COST_CUH

#include "int/instruction.cuh"
#include "int/program.h"

namespace so {
	SO_HD u32 perf_cost(const inst* prog, u32 prog_len, u64 live_mask) {
		u64 live = live_mask;
		u32 count = 0;

		for(i32 i = (i32)prog_len - 1; i >= 0; --i) {
			const inst_spec& spec = find_spec(prog[i].op);

			if(spec.dst_slot < 0) {
				continue;
			}

			const u32 dst = (u32)prog[i].operands[spec.dst_slot].reg;
			const u64 dst_bit = 1ULL << dst;

			if(live & dst_bit) {
				++count;

				if(!spec.rmw) {
					live &= ~dst_bit;
				}

				if(spec.src_slot >= 0) {
					const u32 src = (u32)prog[i].operands[spec.src_slot].reg;
					live |= 1ULL << src;
				}

				if(spec.src2_slot >= 0) {
					const u32 src2 = (u32)prog[i].operands[spec.src2_slot].reg;
					live |= 1ULL << src2;
				}
			}
		}

		return count;
	}
} // namespace so

#endif // #ifndef COST_CUH

