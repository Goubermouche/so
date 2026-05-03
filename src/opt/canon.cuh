#ifndef CANON_CUH
#define CANON_CUH

#include "int/instruction.cuh"

namespace so {
	SO_HD u64 compute_live_in(const inst* prog, u32 prog_len) {
		u64 written = 0;
		u64 live_in = 0;

		for(u32 i = 0; i < prog_len; ++i) {
			const inst_spec& spec = find_spec(prog[i].op);

			if(spec.src_slot >= 0) {
				const u32 r = (u32)prog[i].operands[spec.src_slot].reg;

				if(!(written & (1ULL << r))) {
					live_in |= 1ULL << r;
				}
			}

			if(spec.src2_slot >= 0) {
				const u32 r = (u32)prog[i].operands[spec.src2_slot].reg;

				if(!(written & (1ULL << r))) {
					live_in |= 1ULL << r;
				}
			}

			if(spec.rmw && spec.dst_slot >= 0) {
				const u32 r = (u32)prog[i].operands[spec.dst_slot].reg;

				if(!(written & (1ULL << r))) {
					live_in |= 1ULL << r;
				}
			}

			if(spec.dst_slot >= 0) {
				const u32 r = (u32)prog[i].operands[spec.dst_slot].reg;
				written |= 1ULL << r;
			}
		}

		return live_in;
	}

	SO_HD void canonicalize(inst* prog, u32 prog_len, u64 preserved_mask) {
		u8 rename[16];
		u32 assigned_mask = 0;
		u32 resolved_mask = 0;
		u32 next_scratch = 0;

		for(u32 r = 0; r < 16; ++r) {
			if(preserved_mask & (1ULL << r)) {
				rename[r] = (u8)r;
				resolved_mask |= (1u << r);
				assigned_mask |= (1u << r);
			}
		}

		for(u32 i = 0; i < prog_len; ++i) {
			inst& in = prog[i];
			const inst_spec& spec = find_spec(in.op);

			for(u32 k = 0; k < 4; ++k) {
				if(spec.operands[k] != inst_spec::R64) {
					continue;
				}

				const u32 old = (u32)in.operands[k].reg;

				if(!(resolved_mask & (1u << old))) {
					while(assigned_mask & (1u << next_scratch)) {
						++next_scratch;
					}

					rename[old] = (u8)next_scratch;
					resolved_mask |= (1u << old);
					assigned_mask |= (1u << next_scratch);
				}

				in.operands[k].reg = (reg_index)rename[old];
			}
		}
	}
} // namespace so

#endif // #ifndef CANON_CUH

