#include "opt/enumerate.h"

opt_opcode_pool opt_build_opcode_pool(u32 ext_mask) {
	opt_opcode_pool p = {};

	for(u32 i = 0; i < (u32)OP_COUNT; ++i) {
		const cpu_inst_spec& s = CPU_INST_DB_HOST.row[i];
		if(s.op == OP_NOP) { continue; }
		if(!(s.ext & ext_mask)) { continue; }
		p.ops[p.n_ops++] = (cpu_opcode)i;
	}

	return p;
}

opt_imm_pool opt_build_default_imm_pool() {
	opt_imm_pool p = {};

	for(i64 v = -8; v <= 8; ++v) { p.vals[p.n++] = v; }
	const i64 extra[] = {16, 32, 63, 64, 0xFF, 0xFFFF};
	for(i64 v : extra) { p.vals[p.n++] = v; }

	return p;
}

void opt_enum_backward(opt_enumerator* e, opt_enum_state* s) {
	if(e->out->size >= e->cap) return;

	// we placed all instructions - accept if all remaining demanded
	// registers are live-ins (they'll be provided at runtime)
	if(s->idx < 0) {
		if((s->demanded & ~e->live_in_mask) == 0) {
			opt_candidate emitted = *s->cur;
			emitted.len = e->prog_len;
			opt_candidate_arr_push(e->out, emitted);
		}

		return;
	}

	if(s->demanded == 0) { return; }

	u64 src_avail;

	if(s->idx == 0) {
		src_avail = e->live_in_mask | 1ULL;
	} else {
		src_avail = e->live_in_mask | 1ULL;
		for(u32 r = 5; r < e->max_scratch && r < 32; ++r) { src_avail |= 1ULL << r; }
		src_avail |= e->live_out_mask;
	}

	const u64 dst_avail = s->demanded;

	// iterate opcode -> dst -> sources
	for(u32 oi = 0; oi < e->pool->n_ops; ++oi) {
		const cpu_opcode op = e->pool->ops[oi];
		const cpu_inst_spec& spec = CPU_INST_DB_HOST.row[op];

		b32 has_rs1 = spec.src_slot >= 0;
		b32 has_rs2 = spec.src2_slot >= 0;
		b32 has_imm = false;

		for(u32 k = 0; k < 4; ++k) {
			if(spec.operands[k] == cpu_inst_spec::IMM) { has_imm = true; }
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
						opt_place_attempt a = {op, rd, rs1, rs2, false};
						opt_try_place(e, s, &a);
						if(e->out->size >= e->cap) { return; }
					}
				}
			} else if(has_rs1 && has_imm) {
				u64 a_iter = src_avail;

				while(a_iter) {
					const u32 rs1 = (u32)__builtin_ctzll(a_iter);
					a_iter &= a_iter - 1;

					for(u32 ii = 0; ii < e->imms->n; ++ii) {
						opt_place_attempt a = {op, rd, rs1, ii, true};
						opt_try_place(e, s, &a);
						if(e->out->size >= e->cap) { return; }
					}
				}
			} else if(has_imm) {
				for(u32 ii = 0; ii < e->imms->n; ++ii) {
					opt_place_attempt a = {op, rd, /*rs1*/ 0, ii, true};
					opt_try_place(e, s, &a);
					if(e->out->size >= e->cap) { return; }
				}
			} else if(has_rs1) {
				u64 a_iter = src_avail;

				while(a_iter) {
					const u32 rs1 = (u32)__builtin_ctzll(a_iter);
					a_iter &= a_iter - 1;
					opt_place_attempt a = {op, rd, rs1, 0, false};
					opt_try_place(e, s, &a);
					if(e->out->size >= e->cap) { return; }
				}
			}
		}
	}
}

void opt_try_place(opt_enumerator* e, opt_enum_state* s, const opt_place_attempt* a) {
	if(e->out->size >= e->cap) { return; }
	const cpu_inst_spec& spec = CPU_INST_DB_HOST.row[a->op];
	if(a->rd == 0) { return; }
	if(!(s->demanded & (1ULL << a->rd))) { return; }

	const u64 preserved = e->live_in_mask | e->live_out_mask;
	const b32 rd_is_scratch = !(preserved & (1ULL << a->rd)) && a->rd >= 5;

	if(rd_is_scratch) {
		for(u32 r = 5; r < a->rd; ++r) {
			if(preserved & (1ULL << r)) { continue; }
			if(!(s->used_scratch & (1ULL << r))) { return; }
		}
	}

	// for R-type with two register sources, force rs1 <= rs2
	if(!a->is_imm && spec.src2_slot >= 0 && cpu_op_is_commutative(a->op)) {
		if(a->rs1 > a->rs2_or_imm_idx) { return; }
	}

	// build the instruction
	cpu_inst in = {};
	in.op = a->op;
	in.operands[spec.dst_slot].reg = (cpu_reg_index)a->rd;

	if(spec.src_slot >= 0) { in.operands[spec.src_slot].reg = (cpu_reg_index)a->rs1; }
	if(!a->is_imm && spec.src2_slot >= 0) {
		in.operands[spec.src2_slot].reg = (cpu_reg_index)a->rs2_or_imm_idx;
	}

	if(a->is_imm) {
		for(u32 k = 0; k < 4; ++k) {
			if(spec.operands[k] == cpu_inst_spec::IMM) {
				in.operands[k].i = (u64)e->imms->vals[a->rs2_or_imm_idx];
				break;
			}
		}
	}

	s->cur->code[s->idx] = in;
	u64 new_demanded = s->demanded & ~(1ULL << a->rd);

	if(spec.src_slot >= 0) {
		const u32 r = a->rs1;
		if(r != 0 && !(e->live_in_mask & (1ULL << r))) { new_demanded |= 1ULL << r; }
	}
	if(!a->is_imm && spec.src2_slot >= 0) {
		const u32 r = a->rs2_or_imm_idx;
		if(r != 0 && !(e->live_in_mask & (1ULL << r))) { new_demanded |= 1ULL << r; }
	}

	u64 new_used_scratch = s->used_scratch;
	if(rd_is_scratch) { new_used_scratch |= 1ULL << a->rd; }

	opt_enum_state ns = {s->cur, s->idx - 1, new_demanded, new_used_scratch};
	opt_enum_backward(e, &ns);
}

void opt_enumerate(const opt_enum_config* cfg, opt_candidate_arr* out, u64 cap) {
	opt_enumerator E;
	E.pool = cfg->pool;
	E.imms = cfg->imms;
	E.live_in_mask = cfg->live_in_mask & ~1ULL; // x0 is special
	E.live_out_mask = cfg->live_out_mask;
	E.max_scratch = cfg->max_scratch;
	E.prog_len = cfg->prog_len;
	E.out = out;
	E.cap = cap;

	opt_candidate cur = {};
	opt_enum_state s = {&cur, (i32)cfg->prog_len - 1, cfg->live_out_mask, 0ULL};
	opt_enum_backward(&E, &s);
}
