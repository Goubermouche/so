#ifndef MUTATE_CUH
#define MUTATE_CUH

#include "int/instruction.cuh"

namespace so {
	struct rng {
		u64 s;
	};

	SO_HD u64 rng_next(rng* r) {
		u64 x = r->s;
		x ^= x >> 12;
		x ^= x << 25;
		x ^= x >> 27;
		r->s = x;
		return x * 0x2545F4914F6CDD1DULL;
	}

	SO_HD u32 rng_u32(rng* r, u32 bound) {
		return (u32)(rng_next(r) % bound);
	}

	SO_HD f32 rng_unit(rng* r) {
		return (f32)(rng_next(r) >> 40) * (1.0f / (f32)(1u << 24));
	}

	static constexpr u32 MUTATE_MAX_GROUP_SIZE = 16;

	struct opcode_group {
		opcode ops[MUTATE_MAX_GROUP_SIZE];
		u32 n_ops;
	};

	namespace detail {
		SO_HD constexpr b32 same_signature(const inst_spec& a, const inst_spec& b) {
			for(u32 k = 0; k < 4; ++k) {
				if(a.operands[k] != b.operands[k]) {
					return false;
				}
			}

			return true;
		}

		SO_HD constexpr u32 count_groups() {
			const inst_db_t db = build_inst_db();
			u32 n = 0;

			for(u32 i = 0; i < (u32)OP_COUNT; ++i) {
				b32 seen = false;

				for(u32 j = 0; j < i; ++j) {
					if(same_signature(db.row[i], db.row[j])) {
						seen = true;
						break;
					}
				}

				if(!seen) {
					++n;
				}
			}

			return n;
		}
	} // namespace detail

	static constexpr u32 MUTATE_N_GROUPS = detail::count_groups();

	struct mutation_tables_t {
		opcode_group groups[MUTATE_N_GROUPS];
		u8 opcode_to_group[OP_COUNT];
	};

	namespace detail {
		SO_HD constexpr mutation_tables_t build_mutation_tables() {
			const inst_db_t db = build_inst_db();
			mutation_tables_t t = {};
			u32 gi = 0;

			for(u32 i = 0; i < (u32)OP_COUNT; ++i) {
				i32 found = -1;

				for(u32 g = 0; g < gi; ++g) {
					const u32 rep = (u32)t.groups[g].ops[0];

					if(same_signature(db.row[i], db.row[rep])) {
						found = (i32)g;
						break;
					}
				}

				if(found < 0) {
					t.groups[gi].ops[0] = (opcode)i;
					t.groups[gi].n_ops = 1;
					t.opcode_to_group[i] = (u8)gi;
					++gi;
				}
				else {
					opcode_group& g = t.groups[found];
					g.ops[g.n_ops++] = (opcode)i;
					t.opcode_to_group[i] = (u8)found;
				}
			}

			return t;
		}

		SO_HD constexpr b32 check_group_sizes() {
			const mutation_tables_t t = build_mutation_tables();

			for(u32 g = 0; g < MUTATE_N_GROUPS; ++g) {
				if(t.groups[g].n_ops > MUTATE_MAX_GROUP_SIZE) {
					return false;
				}
			}

			return true;
		}

		static_assert(check_group_sizes(), "MUTATE_MAX_GROUP_SIZE too small for INST_DB");
	} // namespace detail

	inline constexpr mutation_tables_t MUTATION_TABLES_HOST = detail::build_mutation_tables();

#ifdef __CUDACC__
	static __constant__ mutation_tables_t MUTATION_TABLES_DEV = detail::build_mutation_tables();
#endif

	SO_HD const opcode_group& mutate_group(u32 i) {
#ifdef __CUDA_ARCH__
		return MUTATION_TABLES_DEV.groups[i];
#else
		return MUTATION_TABLES_HOST.groups[i];
#endif
	}

	SO_HD u8 mutate_opcode_group(opcode op) {
#ifdef __CUDA_ARCH__
		return MUTATION_TABLES_DEV.opcode_to_group[op];
#else
		return MUTATION_TABLES_HOST.opcode_to_group[op];
#endif
	}

	SO_HD u64 random_immediate(rng* r) {
		const u64 hi = rng_next(r);
		const u64 lo = rng_next(r);
		return (hi & 0xFFFFFFFF00000000ULL) | (lo >> 32);
	}

	SO_HD u64 bitflip_immediate(rng* r, u64 cur) {
		const u32 bit = rng_u32(r, 64);
		return cur ^ (1ULL << bit);
	}

	SO_HD inst::operand random_operand_of(inst_spec::operand type, rng* r) {
		inst::operand o;

		if(type == inst_spec::R64) {
			o.reg = (reg_index)rng_u32(r, 16);
		}
		else if(type == inst_spec::I64) {
			o.i = random_immediate(r);
		}
		else {
			o.i = 0;
		}

		return o;
	}

	SO_HD inst random_inst(rng* r) {
		const opcode op = (opcode)rng_u32(r, OP_COUNT);
		const inst_spec& spec = find_spec(op);
		inst in;
		in.op = op;

		for(u32 k = 0; k < 4; ++k) {
			in.operands[k] = random_operand_of(spec.operands[k], r);
		}

		return in;
	}

	SO_HD void mutate_operand(inst* prog, u32 prog_len, rng* r) {
		const u32 slot = rng_u32(r, prog_len);
		const inst_spec& spec = find_spec(prog[slot].op);
		const u8 nops = spec.get_operand_count();

		if(nops == 0) {
			prog[slot] = random_inst(r);
			return;
		}

		const u32 op_idx = rng_u32(r, nops);
		const inst_spec::operand op_type = spec.operands[op_idx];

		if(op_type == inst_spec::I64) {
			if(rng_u32(r, 16) == 0) {
				prog[slot].operands[op_idx].i = random_immediate(r);
			}
			else {
				prog[slot].operands[op_idx].i = bitflip_immediate(r, prog[slot].operands[op_idx].i);
			}
		}
		else {
			prog[slot].operands[op_idx] = random_operand_of(op_type, r);
		}
	}

	SO_HD void mutate_opcode(inst* prog, u32 prog_len, rng* r) {
		const u32 slot = rng_u32(r, prog_len);
		const u32 gi = mutate_opcode_group(prog[slot].op);
		const opcode_group& g = mutate_group(gi);

		if(g.n_ops <= 1) {
			return; // singleton group
		}

		const opcode cur = prog[slot].op;
		opcode nxt;

		do {
			nxt = g.ops[rng_u32(r, g.n_ops)];
		} while(nxt == cur);

		prog[slot].op = nxt;
	}

	SO_HD void mutate_swap(inst* prog, u32 prog_len, rng* r) {
		if(prog_len < 2) {
			return;
		}

		const u32 a = rng_u32(r, prog_len);
		u32 b = rng_u32(r, prog_len - 1);

		if(b >= a) {
			++b;
		}

		const inst tmp = prog[a];
		prog[a] = prog[b];
		prog[b] = tmp;
	}

	SO_HD void mutate_instruction(inst* prog, u32 prog_len, rng* r) {
		const u32 slot = rng_u32(r, prog_len);

		if(rng_unit(r) < 0.16f) {
			prog[slot].op = OP_NOP;
			for(u32 k = 0; k < 4; ++k) {
				prog[slot].operands[k].i = 0;
			}
		}
		else {
			prog[slot] = random_inst(r);
		}
	}

	SO_HD u32 mutate_one(inst* prog, u32 prog_len, rng* r) {
		const u32 which = rng_u32(r, 4);

		switch(which) {
			case 0: mutate_operand(prog, prog_len, r); break;
			case 1: mutate_opcode(prog, prog_len, r); break;
			case 2: mutate_swap(prog, prog_len, r); break;
			case 3: mutate_instruction(prog, prog_len, r); break;
		}

		return which;
	}
} // namespace so

#endif // #ifndef MUTATE_CUH

