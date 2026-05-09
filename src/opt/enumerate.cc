#include "opt/enumerate.h"

opt_opcode_pool opt_build_opcode_pool(u32 ext_mask) {
	opt_opcode_pool p = {};

	for(u32 i = 0; i < (u32)OP_COUNT; ++i) {
		const int_inst_spec& s = INT_INST_DB_HOST.row[i];
		if(s.op == OP_NOP) { continue; }
		if(!(s.ext & ext_mask)) { continue; }
		p.ops[p.n_ops++] = (int_opcode)i;
	}

	return p;
}

b32 opt_op_is_commutative(int_opcode op) { return INT_INST_DB_HOST.row[op].commutative != 0; }

opt_imm_pool opt_build_default_imm_pool() {
	opt_imm_pool p = {};

	for(i64 v = -8; v <= 8; ++v) { p.vals[p.n++] = v; }
	const i64 extra[] = {16, 32, 63, 64, 0xFF, 0xFFFF};
	for(i64 v : extra) { p.vals[p.n++] = v; }

	return p;
}

void opt_enum_backward(opt_enumerator* e, opt_candidate* cur, u32 prog_len, i32 idx, u64 demanded,
											 u64 used_scratch) {
	if(e->out->size() >= e->cap) return;

	// we placed all instructions - accept if all remaining demanded
	// registers are live-ins (they'll be provided at runtime)
	if(idx < 0) {
		if((demanded & ~e->live_in_mask) == 0) {
			opt_candidate emitted = *cur;
			emitted.len = prog_len;
			e->out->push_back(emitted);
		}

		return;
	}

	if(demanded == 0) { return; }

	u64 src_avail;

	if(idx == 0) {
		src_avail = e->live_in_mask | 1ULL;
	} else {
		src_avail = e->live_in_mask | 1ULL;
		for(u32 r = 5; r < e->max_scratch && r < 32; ++r) { src_avail |= 1ULL << r; }
		src_avail |= e->live_out_mask;
	}

	const u64 dst_avail = demanded;

	// iterate opcode -> dst -> sources
	for(u32 oi = 0; oi < e->pool->n_ops; ++oi) {
		const int_opcode op = e->pool->ops[oi];
		const int_inst_spec& spec = INT_INST_DB_HOST.row[op];

		b32 has_rs1 = spec.src_slot >= 0;
		b32 has_rs2 = spec.src2_slot >= 0;
		b32 has_imm = false;

		for(u32 k = 0; k < 4; ++k) {
			if(spec.operands[k] == int_inst_spec::IMM) { has_imm = true; }
		}

		u64 dst_iter = dst_avail;

		while(dst_iter) {
			const u32 rd = (u32)__builtin_ctzll(dst_iter);
			dst_iter &= dst_iter - 1;

			if(has_rs1 && has_rs2) {
				u64 a_iter = src_avail;

				while(a_iter) {
					const u32 rs1 = (u32)__builtin_ctzll(a_iter);
					a_iter &= a_iter - 1;
					u64 b_iter = src_avail;

					while(b_iter) {
						const u32 rs2 = (u32)__builtin_ctzll(b_iter);
						b_iter &= b_iter - 1;
						opt_try_place(e, cur, prog_len, idx, op, rd, rs1, rs2, false, demanded, used_scratch);
						if(e->out->size() >= e->cap) { return; }
					}
				}
			} else if(has_rs1 && has_imm) {
				u64 a_iter = src_avail;

				while(a_iter) {
					const u32 rs1 = (u32)__builtin_ctzll(a_iter);
					a_iter &= a_iter - 1;

					for(u32 ii = 0; ii < e->imms->n; ++ii) {
						opt_try_place(e, cur, prog_len, idx, op, rd, rs1, ii, true, demanded, used_scratch);
						if(e->out->size() >= e->cap) { return; }
					}
				}
			} else if(has_imm) {
				for(u32 ii = 0; ii < e->imms->n; ++ii) {
					opt_try_place(e, cur, prog_len, idx, op, rd, /*rs1*/ 0, ii, true, demanded, used_scratch);
					if(e->out->size() >= e->cap) { return; }
				}
			} else if(has_rs1) {
				u64 a_iter = src_avail;

				while(a_iter) {
					const u32 rs1 = (u32)__builtin_ctzll(a_iter);
					a_iter &= a_iter - 1;
					opt_try_place(e, cur, prog_len, idx, op, rd, rs1, 0, false, demanded, used_scratch);
					if(e->out->size() >= e->cap) { return; }
				}
			}
		}
	}
}

void opt_try_place(opt_enumerator* e, opt_candidate* cur, u32 prog_len, i32 idx, int_opcode op, u32 rd,
									 u32 rs1, u32 rs2_or_imm_idx, b32 is_imm, u64 demanded, u64 used_scratch) {
	if(e->out->size() >= e->cap) { return; }
	const int_inst_spec& spec = INT_INST_DB_HOST.row[op];
	if(rd == 0) { return; }
	if(!(demanded & (1ULL << rd))) { return; }

	const u64 preserved = e->live_in_mask | e->live_out_mask;
	const b32 rd_is_scratch = !(preserved & (1ULL << rd)) && rd >= 5;

	if(rd_is_scratch) {
		for(u32 r = 5; r < rd; ++r) {
			if(preserved & (1ULL << r)) { continue; }
			if(!(used_scratch & (1ULL << r))) { return; }
		}
	}

	// for R-type with two register sources, force rs1 <= rs2
	if(!is_imm && spec.src2_slot >= 0 && opt_op_is_commutative(op)) {
		if(rs1 > rs2_or_imm_idx) { return; }
	}

	// build the instruction
	int_inst in = {};
	in.op = op;
	in.operands[spec.dst_slot].reg = (int_reg_index)rd;

	if(spec.src_slot >= 0) { in.operands[spec.src_slot].reg = (int_reg_index)rs1; }
	if(!is_imm && spec.src2_slot >= 0) {
		in.operands[spec.src2_slot].reg = (int_reg_index)rs2_or_imm_idx;
	}

	if(is_imm) {
		for(u32 k = 0; k < 4; ++k) {
			if(spec.operands[k] == int_inst_spec::IMM) {
				in.operands[k].i = (u64)e->imms->vals[rs2_or_imm_idx];
				break;
			}
		}
	}

	cur->code[idx] = in;
	u64 new_demanded = demanded & ~(1ULL << rd);

	if(spec.src_slot >= 0) {
		const u32 r = rs1;
		if(r != 0 && !(e->live_in_mask & (1ULL << r))) { new_demanded |= 1ULL << r; }
	}
	if(!is_imm && spec.src2_slot >= 0) {
		const u32 r = rs2_or_imm_idx;
		if(r != 0 && !(e->live_in_mask & (1ULL << r))) { new_demanded |= 1ULL << r; }
	}

	u64 new_used_scratch = used_scratch;
	if(rd_is_scratch) { new_used_scratch |= 1ULL << rd; }
	opt_enum_backward(e, cur, prog_len, idx - 1, new_demanded, new_used_scratch);
}

void opt_enumerate(const opt_opcode_pool* pool, const opt_imm_pool* imms, u64 live_in_mask,
									 u64 live_out_mask, u32 prog_len, u32 max_scratch, arr<opt_candidate>* out,
									 u64 cap) {
	opt_enumerator E;
	E.pool = pool;
	E.imms = imms;
	E.live_in_mask = live_in_mask & ~1ULL; // x0 is special
	E.live_out_mask = live_out_mask;
	E.max_scratch = max_scratch;
	E.out = out;
	E.cap = cap;

	opt_candidate cur = {};
	const u64 initial_demanded = live_out_mask;
	opt_enum_backward(&E, &cur, prog_len, (i32)prog_len - 1, initial_demanded, 0ULL);
}
