#include "cpu/program.h"
#include "lexer/lexer.h"

namespace sup {

program program::parse(arena& a, string source) {
	array<inst> result;
	lexer lex = lex_make(source);
	lex_next_char(&lex);
	lex_next_tok(&lex);

	while(lex.curr != token::END_OF_FILE) {
		// skip leading blank lines between instructions
		while(lex.curr == token::NEWLINE) lex_next_tok(&lex);
		if(lex.curr == token::END_OF_FILE) break;

		if(lex.curr == token::IDENTIFIER) {
			string saved = lex.curr_string;
			lex_next_tok(&lex);
			if(lex.curr == token::COLON) {
				lex_next_tok(&lex);
				if(lex.curr == token::NEWLINE) lex_next_tok(&lex);
				continue;
			}
			// not a label after all - rewind by re-parsing as a mnemonic
			inst curr_inst = {};
			operand_type operand_types[4] = {};
			u8 operand_count = 0;

			while(lex.curr != token::NEWLINE && lex.curr != token::END_OF_FILE &&
						operand_count < 4) {
				if(lex_token_is_reg(lex.curr)) {
					curr_inst.operands[operand_count].reg =
						(reg_index)(lex_token_to_reg_index(lex.curr));
					operand_types[operand_count] = OPERAND_REG;
				} else if(lex.curr == token::NUMBER) {
					curr_inst.operands[operand_count].i = (u64)lex.curr_imm;
					operand_types[operand_count] = OPERAND_IMM;
				} else if(lex.curr == token::MINUS) {
					lex_next_tok(&lex);
					ASSERT(lex.curr == token::NUMBER, "expected number after '-'");
					curr_inst.operands[operand_count].i = (u64)(-lex.curr_imm);
					operand_types[operand_count] = OPERAND_IMM;
				} else {
					ASSERT(false, "unrecognized operand type received ('%s')",
								 lex_token_to_str(lex.curr));
				}

				operand_count++;

				if(lex_next_tok(&lex) != token::COMMA) break;
				lex_next_tok(&lex);
			}

			// pseudo-op rewriting
			//   sext.w rd, rs1   ->   addiw rd, rs1, 0
			if(saved == "sext.w" && operand_count == 2 &&
				 operand_types[0] == OPERAND_REG && operand_types[1] == OPERAND_REG) {
				saved = "addiw";
				curr_inst.operands[2].i = 0;
				operand_types[2] = OPERAND_IMM;
				operand_count = 3;
			}

			curr_inst.op = find_inst_op(saved, operand_types, operand_count);
			ASSERT(curr_inst.op != OP_COUNT,
						 "no opcode matches mnemonic '%.*s' with %d operand(s)\n",
						 (int)saved.size, (const c8*)saved.ptr, (int)operand_count);
			result.push(curr_inst);

			if(lex.curr == token::NEWLINE) { lex_next_tok(&lex); }
			continue;
		}

		ASSERT(false, "expected mnemonic, got '%s'", lex_token_to_str(lex.curr));
	}

	inst* data = a.push<inst>(result.size);
	memcpy(data, result.ptr, sizeof(inst) * result.size);
	program out = {data, result.size};
	return out;
}

string program::to_string(arena& a) const {
	array<string> builder;

	for(u32 i = 0; i < size; ++i) {
		const inst inst = ptr[i];
		const inst_spec* spec = find_spec(inst.op);
		builder.push("  ");
		string inst_name = string(spec->name);
		inst_name.pad(a, ' ', 8);
		builder.push(inst_name);

		const u8 nop = spec_get_operand_count(spec);
		for(u8 j = 0; j < nop; ++j) {
			builder.push(operand_to_string(a, inst.operands[j], spec->operands[j]));
			if(j + 1 < nop) { builder.push(", "); }
		}

		builder.push("\n");
	}

	return str_list_flatten(a, builder, "");
}

u64 program::get_live_out() const {
	u64 touched = 0;
	u64 live_out = 0;

	for(u64 idx = size; idx-- > 0;) {
		const inst& in = ptr[idx];
		const inst_spec* spec = find_spec(in.op);

		// write side first
		if(spec->dst_slot >= 0) {
			const u32 r = (u32)in.operands[spec->dst_slot].reg;

			// x0 writes don't define anything
			if(r != 0) {
				const u64 bit = 1ULL << r;

				if(!(touched & bit)) {
					live_out |= bit;
					touched |= bit;
				}
			}
		}

		// read side
		if(spec->src_slot >= 0) {
			const u32 r = (u32)in.operands[spec->src_slot].reg;
			touched |= 1ULL << r;
		}

		if(spec->src2_slot >= 0) {
			const u32 r = (u32)in.operands[spec->src2_slot].reg;
			touched |= 1ULL << r;
		}
	}

	return live_out;
}

u64 program::get_live_in() const {
	u64 written = 0;
	u64 live_in = 0;

	for(u32 i = 0; i < size; ++i) {
		const inst_spec* spec = find_spec(ptr[i].op);

		if(spec->src_slot >= 0) {
			const u32 r = (u32)ptr[i].operands[spec->src_slot].reg;
			if(!(written & (1ull << r))) { live_in |= 1ull << r; }
		}

		if(spec->src2_slot >= 0) {
			const u32 r = (u32)ptr[i].operands[spec->src2_slot].reg;
			if(!(written & (1ull << r))) { live_in |= 1ull << r; }
		}

		if(spec->dst_slot >= 0) {
			const u32 r = (u32)ptr[i].operands[spec->dst_slot].reg;
			written |= 1ull << r;
		}
	}

	return live_in & ~1ull; // remove x0
}
} // namespace sup