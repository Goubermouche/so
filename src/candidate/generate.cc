#include "generate.h"

namespace so {
	bool is_valid_next(const arr<inst>& prog, const inst& next) {
		// TODO: remove pointless candidates
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
			next.ops[0] = dst;
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
				next.ops[0] = dst;
				next.ops[1] = src;
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
				next.ops[0] = dst;
				next.ops[1] = imm;
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
