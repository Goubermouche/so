#ifndef ENUMERATE_CUH
#define ENUMERATE_CUH

#include "int/instruction.cuh"
#include "opt/canon.cuh"

namespace sup {
	struct opcode_pool {
		opcode ops[OP_COUNT];
		u32 n_ops;
	};

	inline opcode_pool build_opcode_pool(u32 ext_mask) {
		opcode_pool p = {};

		for(u32 i = 0; i < (u32)OP_COUNT; ++i) {
			const inst_spec& s = INST_DB_HOST.row[i];

			if(s.op == OP_NOP) {
				continue;
			}

			if(!(s.ext & ext_mask)) {
				continue;
			}

			p.ops[p.n_ops++] = (opcode)i;
		}

		return p;
	}

	inline b32 op_is_commutative(opcode op) {
		return INST_DB_HOST.row[op].commutative != 0;
	}

	struct imm_pool {
		i64 vals[64];
		u32 n;
	};

	inline imm_pool build_default_imm_pool() {
		imm_pool p = {};

		for(i64 v = -8; v <= 8; ++v) {
			p.vals[p.n++] = v;
		}

		const i64 extra[] = { 16, 32, 63, 64, 0xFF, 0xFFFF };

		for(i64 v : extra) {
			p.vals[p.n++] = v;
		}

		return p;
	}

	template<u32 MAX_LEN>
	struct candidate {
		inst code[MAX_LEN];
		u32 len;
	};

	template<u32 MAX_LEN>
	struct enumerator {
		const opcode_pool* pool;
		const imm_pool* imms;
		u64 live_in_mask;
		u64 live_out_mask;
		u32 max_scratch;
		arr<candidate<MAX_LEN>>* out;
		u64 cap;
	};

	template<u32 MAX_LEN>
	void enum_backward(enumerator<MAX_LEN>& E, candidate<MAX_LEN>& cur, u32 prog_len, i32 idx, u64 demanded, u64 used_scratch);

	template<u32 MAX_LEN>
	inline void try_place(enumerator<MAX_LEN>& E, candidate<MAX_LEN>& cur, u32 prog_len, i32 idx, opcode op, u32 rd, u32 rs1, u32 rs2_or_imm_idx, b32 is_imm, u64 demanded, u64 used_scratch) {
		if(E.out->size() >= E.cap) {
			return;
		}

		const inst_spec& spec = INST_DB_HOST.row[op];

		if(rd == 0) {
			return;
		}

		if(!(demanded & (1ULL << rd))) {
			return;
		}

		const u64 preserved = E.live_in_mask | E.live_out_mask;
		const b32 rd_is_scratch = !(preserved & (1ULL << rd)) && rd >= 5;

		if(rd_is_scratch) {
			for(u32 r = 5; r < rd; ++r) {
				if(preserved & (1ULL << r)) {
					continue;
				}

				if(!(used_scratch & (1ULL << r))) {
					return;
				}
			}
		}

		// for R-type with two register sources, force rs1 <= rs2
		if(!is_imm && spec.src2_slot >= 0 && op_is_commutative(op)) {
			if(rs1 > rs2_or_imm_idx) {
				return;
			}
		}

		// build the instruction
		inst in = {};
		in.op = op;
		in.operands[spec.dst_slot].reg = (reg_index)rd;

		if(spec.src_slot  >= 0) {
			in.operands[spec.src_slot ].reg = (reg_index)rs1;
		}

		if(!is_imm && spec.src2_slot >= 0) {
			in.operands[spec.src2_slot].reg = (reg_index)rs2_or_imm_idx;
		}

		if(is_imm) {
			for(u32 k = 0; k < 4; ++k) {
				if(spec.operands[k] == inst_spec::IMM) {
					in.operands[k].i = (u64)E.imms->vals[rs2_or_imm_idx];
					break;
				}
			}
		}

		cur.code[idx] = in;
		u64 new_demanded = demanded & ~(1ULL << rd);

		if(spec.src_slot >= 0) {
			const u32 r = rs1;

			if(r != 0 && !(E.live_in_mask & (1ULL << r))) {
				new_demanded |= 1ULL << r;
			}
		}
		if(!is_imm && spec.src2_slot >= 0) {
			const u32 r = rs2_or_imm_idx;

			if(r != 0 && !(E.live_in_mask & (1ULL << r))) {
				new_demanded |= 1ULL << r;
			}
		}

		u64 new_used_scratch = used_scratch;

		if(rd_is_scratch) {
			new_used_scratch |= 1ULL << rd;
		}

		enum_backward(E, cur, prog_len, idx - 1, new_demanded, new_used_scratch);
	}

	template<u32 MAX_LEN>
	void enum_backward(enumerator<MAX_LEN>& E, candidate<MAX_LEN>& cur, u32 prog_len, i32 idx, u64 demanded, u64 used_scratch) {
		if(E.out->size() >= E.cap) return;

		// we placed all instructions - accept if all remaining demanded
		// registers are live-ins (they'll be provided at runtime)
		if(idx < 0) {
			if((demanded & ~E.live_in_mask) == 0) {
				candidate<MAX_LEN> emitted = cur;
				emitted.len = prog_len;
				E.out->push_back(emitted);
			}

			return;
		}

		if(demanded == 0) {
			return;
		}

		u64 src_avail;

		if(idx == 0) {
			src_avail = E.live_in_mask | 1ULL;
		}
		else {
			src_avail = E.live_in_mask | 1ULL;

			for(u32 r = 5; r < E.max_scratch && r < 32; ++r) {
				src_avail |= 1ULL << r;
			}

			src_avail |= E.live_out_mask;
		}

		const u64 dst_avail = demanded;

		// iterate opcode -> dst -> sources
		for(u32 oi = 0; oi < E.pool->n_ops; ++oi) {
			const opcode op = E.pool->ops[oi];
			const inst_spec& spec = INST_DB_HOST.row[op];

			b32 has_rs1 = spec.src_slot  >= 0;
			b32 has_rs2 = spec.src2_slot >= 0;
			b32 has_imm = false;

			for(u32 k = 0; k < 4; ++k) {
				if(spec.operands[k] == inst_spec::IMM) {
					has_imm = true;
				}
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
							try_place(E, cur, prog_len, idx, op, rd, rs1, rs2, false, demanded, used_scratch);

							if(E.out->size() >= E.cap) {
								return;
							}
						}
					}
				}
				else if(has_rs1 && has_imm) {
					u64 a_iter = src_avail;

					while(a_iter) {
						const u32 rs1 = (u32)__builtin_ctzll(a_iter);
						a_iter &= a_iter - 1;

						for(u32 ii = 0; ii < E.imms->n; ++ii) {
							try_place(E, cur, prog_len, idx, op, rd, rs1, ii, true, demanded, used_scratch);

							if(E.out->size() >= E.cap) {
								return;
							}
						}
					}
				}
				else if(has_imm) {
					for(u32 ii = 0; ii < E.imms->n; ++ii) {
						try_place(E, cur, prog_len, idx, op, rd, /*rs1*/0, ii, true, demanded, used_scratch);

						if(E.out->size() >= E.cap) {
							return;
						}
					}
				}
				else if(has_rs1) {
					u64 a_iter = src_avail;

					while(a_iter) {
						const u32 rs1 = (u32)__builtin_ctzll(a_iter);
						a_iter &= a_iter - 1;
						try_place(E, cur, prog_len, idx, op, rd, rs1, 0, false, demanded, used_scratch);

						if(E.out->size() >= E.cap) {
							return;
						}
					}
				}
			}
		}
	}

	template<u32 MAX_LEN>
	void enumerate_programs(const opcode_pool& pool, const imm_pool& imms, u64 live_in_mask, u64 live_out_mask, u32 prog_len, u32 max_scratch, arr<candidate<MAX_LEN>>& out, u64 cap = (u64)-1) {
		enumerator<MAX_LEN> E;
		E.pool = &pool;
		E.imms = &imms;
		E.live_in_mask  = live_in_mask & ~1ULL; // x0 is special
		E.live_out_mask = live_out_mask;
		E.max_scratch = max_scratch;
		E.out = &out;
		E.cap = cap;

		candidate<MAX_LEN> cur = {};
		const u64 initial_demanded = live_out_mask;
		enum_backward<MAX_LEN>(E, cur, prog_len, (i32)prog_len - 1, initial_demanded, 0ULL);
	}
} // namespace sup

#endif // #ifndef ENUMERATE_CUH

