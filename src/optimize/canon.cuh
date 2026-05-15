#ifndef OPT_CANON_CUH
#define OPT_CANON_CUH

#include "cpu/instruction.cuh"

SO_HD u64 opt_compute_live_in(const cpu_inst* prog, u32 prog_len) {
	u64 written = 0;
	u64 live_in = 0;

	for(u32 i = 0; i < prog_len; ++i) {
		const cpu_inst_spec* spec = cpu_find_spec(prog[i].op);

		if(spec->src_slot >= 0) {
			const u32 r = (u32)prog[i].operands[spec->src_slot].reg;
			if(!(written & (1ull << r))) { live_in |= 1ull << r; }
		}

		if(spec->src2_slot >= 0) {
			const u32 r = (u32)prog[i].operands[spec->src2_slot].reg;
			if(!(written & (1ull << r))) { live_in |= 1ull << r; }
		}

		if(spec->dst_slot >= 0) {
			const u32 r = (u32)prog[i].operands[spec->dst_slot].reg;
			written |= 1ull << r;
		}
	}

	return live_in & ~1ull; // remove x0
}

SO_HD void opt_canonicalize(cpu_inst* prog, u32 prog_len, u64 preserved_mask) {
	u8 rename[32];
	u32 assigned_mask = 0;
	u32 resolved_mask = 0;
	u32 next_scratch = 5; // x5 = first non-ABI scratch

	rename[0] = 0; // pin x0
	resolved_mask |= 1u;
	assigned_mask |= 1u;

	// preserved registers map to themselves
	for(u32 r = 1; r < 32; ++r) {
		if(preserved_mask & (1ull << r)) {
			rename[r] = (u8)r;
			resolved_mask |= (1u << r);
			assigned_mask |= (1u << r);
		}
	}

	for(u32 i = 0; i < prog_len; ++i) {
		cpu_inst& in = prog[i];
		const cpu_inst_spec* spec = cpu_find_spec(in.op);

		for(u32 k = 0; k < 4; ++k) {
			if(spec->operands[k] != CPU_OPERAND_REG) { continue; }

			const u32 old = (u32)in.operands[k].reg;

			if(!(resolved_mask & (1u << old))) {
				while(next_scratch < 32 && (assigned_mask & (1u << next_scratch))) { ++next_scratch; }
				if(next_scratch >= 32) {
					rename[old] = (u8)old;
				} else {
					rename[old] = (u8)next_scratch;
					assigned_mask |= (1u << next_scratch);
				}
				resolved_mask |= (1u << old);
			}

			in.operands[k].reg = (cpu_reg_index)rename[old];
		}
	}
}

SO_HD b32 opt_has_live_writes(const cpu_inst* prog, u32 prog_len, u64 live_mask) {
	u64 live = live_mask & ~1ULL;
	u32 useful = 0;

	for(i32 i = (i32)prog_len - 1; i >= 0; --i) {
		const cpu_inst_spec* spec = cpu_find_spec(prog[i].op);
		if(spec->dst_slot < 0) { continue; }

		const u32 dst = (u32)prog[i].operands[spec->dst_slot].reg;
		if(dst == 0) { continue; }

		const u64 dst_bit = 1ull << dst;

		if(live & dst_bit) {
			++useful;
			live &= ~dst_bit;
			if(spec->src_slot >= 0) { live |= 1ull << (u32)prog[i].operands[spec->src_slot].reg; }
			if(spec->src2_slot >= 0) { live |= 1ull << (u32)prog[i].operands[spec->src2_slot].reg; }
		}
	}

	return useful == prog_len;
}

#endif // #ifndef OPT_CANON_CUH
