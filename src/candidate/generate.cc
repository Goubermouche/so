#include "generate.h"

namespace so {
	bool is_valid_next(const arr<inst>& prog, const inst& next) {
	inst_opcode op = tag_opcode(next.tag);
	u32 op_count = tag_op_count(next.tag);

	// identity no-ops
	if(op_count == 2 && tag_op(next.tag, 0) == OP_R && tag_op(next.tag, 1) == OP_R) {
		if(next.ops[0].r == next.ops[1].r) {
			if(op == INST_MOV || op == INST_AND) {
				return false;
			}
		}
	}

	// sub r, 0
	if(op == INST_SUB && tag_op(next.tag, 1) == OP_I && next.ops[1].i == 0) {
		return false;
	}

	if(prog.empty()) {
		return true;
	}

	const inst& prev = prog.back();
	inst_opcode prev_op = tag_opcode(prev.tag);
	u32 prev_op_count = tag_op_count(prev.tag);

	bool prev_has_dst = (prev_op_count > 0);
	bool next_has_dst = (op_count > 0);

	if(prev_has_dst && next_has_dst && prev.ops[0].r == next.ops[0].r) {
		// dead write
		if (op == INST_MOV && tag_op(next.tag, 1) == OP_R) {
			return false;
		}

		// self-cancelling pairs
		if(prev_op == INST_NOT && op == INST_NOT) {
			return false;
		}

		if(prev_op == INST_NEG && op == INST_NEG) {
			return false;
		}

		// neg + not or not + neg
		if(prev_op == INST_NEG && op == INST_NOT) {
			return false;
		}

		if(prev_op == INST_NOT && op == INST_NEG) {
			return false;
		}
	}

	// redundant mov chain
	if(
		prev_op == INST_MOV &&
		op == INST_MOV &&
		prev_op_count == 2 &&
		op_count == 2 &&
		tag_op(prev.tag, 1) == OP_R &&
		tag_op(next.tag, 1) == OP_R &&
		prev.ops[0].r == next.ops[1].r
	) {
		return false;
	}

	return true;
}
	void try_candidate(
		arr<inst>& current,
		u32 target_len,
		const arr<inst_opcode>& opcodes,
		const arr<u8>& regs,
		arr<inst>& out_flat,
		inst next
	) {
		if(is_valid_next(current, next)) {
			current.push_back(next);
			generate_candidates(current, target_len, opcodes, regs, out_flat);
			current.pop_back();
		}
	}

	void emit_nullary(
		arr<inst>& current,
		u32 target_len,
		const arr<inst_opcode>& opcodes,
		const arr<u8>& regs,
		arr<inst>& out_flat,
		inst_tag tag
	) {
		inst next{};
		next.tag = tag;
		try_candidate(current, target_len, opcodes, regs, out_flat, next);
	}

	void emit_unary(
		arr<inst>& current,
		u32 target_len,
		const arr<inst_opcode>& opcodes,
		const arr<u8>& regs,
		arr<inst>& out_flat,
		inst_tag tag
	) {
		for(u8 dst : regs) {
			inst next{};
			next.tag = tag;
			next.ops[0].r = dst;
			try_candidate(current, target_len, opcodes, regs, out_flat, next);
		}
	}

	void emit_binary_rr(
		arr<inst>& current,
		u32 target_len,
		const arr<inst_opcode>& opcodes,
		const arr<u8>& regs,
		arr<inst>& out_flat,
		inst_tag tag
	) {
		for(u8 dst : regs) {
			for(u8 src : regs) {
				inst next{};
				next.tag = tag;
				next.ops[0].r = dst;
				next.ops[1].r = src;
				try_candidate(current, target_len, opcodes, regs, out_flat, next);
			}
		}
	}

	void emit_binary_ri(
		arr<inst>& current,
		u32 target_len,
		const arr<inst_opcode>& opcodes,
		const arr<u8>& regs,
		arr<inst>& out_flat,
		inst_tag tag,
		const arr<u64>& immediates
	) {
		for(u8 dst : regs) {
			for(u64 imm : immediates) {
				inst next{};
				next.tag = tag;
				next.ops[0].r = dst;
				next.ops[1].i = imm;
				try_candidate(current, target_len, opcodes, regs, out_flat, next);
			}
		}
	}

	void generate_candidates(
		arr<inst>& current,
		u32 target_len,
		const arr<inst_opcode>& opcodes,
		const arr<u8>& regs,
		arr<inst>& out_flat
	) {
		if(static_cast<u32>(current.size()) == target_len) {
			for(const auto& i : current) {
				out_flat.push_back(i);
			}

			return;
		}

		static const arr<u64> immediates = { 0ull, 1ull, 2ull };

		for(inst_opcode op : opcodes) {
			for(u32 v = 0; v < INSTRUCTION_DB_SIZE; ++v) {
				if(tag_opcode(INSTRUCTION_DB[v].tag) != op) continue;

				inst_tag tag = INSTRUCTION_DB[v].tag;
				u32 op_count = tag_op_count(tag);

				if(op_count == 0) {
					emit_nullary(current, target_len, opcodes, regs, out_flat, tag);
				}
				else if (op_count == 1) {
					emit_unary(current, target_len, opcodes, regs, out_flat, tag);
				}
				else if(tag_op(tag, 1) == OP_R) {
					emit_binary_rr(current, target_len, opcodes, regs, out_flat, tag);
				}
				else if(tag_op(tag, 1) == OP_I) {
					emit_binary_ri(current, target_len, opcodes, regs, out_flat, tag, immediates);
				}
			}
		}
	}

} // namespace so
