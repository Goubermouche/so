#include "int/program.h"
#include "int/lexer.h"

int_program int_parse(const str& source) {
	arr<int_inst> result;
	int_lexer lex = int_lexer_make(source);
	int_lexer_next_char(&lex);
	int_lexer_next_tok(&lex);

	while(lex.curr != TOK_EOF) {
		// skip leading blank lines between instructions
		while(lex.curr == TOK_NEWLINE) int_lexer_next_tok(&lex);
		if(lex.curr == TOK_EOF) break;

		if(lex.curr == TOK_IDENTIFIER) {
			str saved = lex.curr_string;
			int_lexer_next_tok(&lex);
			if(lex.curr == TOK_COLON) {
				int_lexer_next_tok(&lex);
				if(lex.curr == TOK_NEWLINE) int_lexer_next_tok(&lex);
				continue;
			}
			// not a label after all - rewind by re-parsing as a mnemonic
			int_inst curr_inst = {};
			int_inst_spec::operand operand_types[4] = {};
			u8 operand_count = 0;

			while(lex.curr != TOK_NEWLINE && lex.curr != TOK_EOF && operand_count < 4) {
				if(int_token_is_reg(lex.curr)) {
					curr_inst.operands[operand_count].reg = (int_reg_index)(int_token_to_reg_index(lex.curr));
					operand_types[operand_count] = int_inst_spec::REG;
				} else if(lex.curr == TOK_NUMBER) {
					curr_inst.operands[operand_count].i = (u64)lex.curr_imm;
					operand_types[operand_count] = int_inst_spec::IMM;
				} else if(lex.curr == TOK_MINUS) {
					int_lexer_next_tok(&lex);
					ASSERT(lex.curr == TOK_NUMBER, "expected number after '-'");
					curr_inst.operands[operand_count].i = (u64)(-lex.curr_imm);
					operand_types[operand_count] = int_inst_spec::IMM;
				} else {
					ASSERT(false, "unrecognized operand type received ('%s')", int_token_to_str(lex.curr));
				}

				operand_count++;

				if(int_lexer_next_tok(&lex) != TOK_COMMA) break;
				int_lexer_next_tok(&lex);
			}

			// pseudo-op rewriting
			//   sext.w rd, rs1   ->   addiw rd, rs1, 0
			if(saved == "sext.w" && operand_count == 2 && operand_types[0] == int_inst_spec::REG &&
				 operand_types[1] == int_inst_spec::REG) {
				saved = "addiw";
				curr_inst.operands[2].i = 0;
				operand_types[2] = int_inst_spec::IMM;
				operand_count = 3;
			}

			curr_inst.op = int_find_inst_op(saved, operand_types, operand_count);
			ASSERT(curr_inst.op != OP_COUNT, "no opcode matches mnemonic '%s' with %d operand(s)\n",
						 saved.c_str(), (int)operand_count);
			result.push_back(curr_inst);

			if(lex.curr == TOK_NEWLINE) { int_lexer_next_tok(&lex); }
			continue;
		}

		ASSERT(false, "expected mnemonic, got '%s'", int_token_to_str(lex.curr));
	}

	int_inst* data = (int_inst*)malloc(sizeof(int_inst) * result.size());
	memcpy(data, result.data(), sizeof(int_inst) * result.size());
	return {data, (u32)result.size()};
}

void int_program_free(const int_program* program) { free(program->instructions); }

int_program int_dce(const int_program* program, u64 live_mask) {
	// x0 is never live in the user-facing sense (writes are dropped)
	u64 live = live_mask & ~1ULL;
	u64 live_bits_by_slot = 0;
	u32 count = 0;

	for(i32 i = (i32)program->size - 1; i >= 0; --i) {
		const int_inst_spec* spec = int_find_spec(program->instructions[i].op);

		if(spec->dst_slot < 0) { continue; }

		const u32 dst = (u32)program->instructions[i].operands[spec->dst_slot].reg;

		// writes to x0 are nops
		if(dst == 0) { continue; }

		const u64 dst_bit = 1ULL << dst;

		if(live & dst_bit) {
			++count;
			live_bits_by_slot |= (1ULL << i);

			// no rmw semantics
			live &= ~dst_bit;

			if(spec->src_slot >= 0) {
				const u32 src = (u32)program->instructions[i].operands[spec->src_slot].reg;
				live |= 1ULL << src;
			}

			if(spec->src2_slot >= 0) {
				const u32 src2 = (u32)program->instructions[i].operands[spec->src2_slot].reg;
				live |= 1ULL << src2;
			}
		}
	}

	int_program out;
	out.size = 0;
	for(u32 i = 0; i < program->size; ++i) {
		if(live_bits_by_slot & (1ULL << i)) { out.size++; }
	}
	out.instructions = (int_inst*)malloc(sizeof(int_inst) * out.size);
	u32 index = 0;
	for(u32 i = 0; i < program->size; ++i) {
		if(live_bits_by_slot & (1ULL << i)) { out.instructions[index++] = program->instructions[i]; }
	}

	return out;
}

str int_program_to_string(const int_program* program) {
	str result;

	for(u32 i = 0; i < program->size; ++i) {
		const int_inst inst = program->instructions[i];
		const int_inst_spec* spec = int_find_spec(inst.op);
		result += "    " + pad_to_length(spec->name, ' ', 8);

		for(u8 j = 0; j < int_spec_get_operand_count(spec); ++j) {
			result += int_operand_to_string(inst.operands[j], spec->operands[j]);
			if(j + 1 < int_spec_get_operand_count(spec)) { result += ", "; }
		}

		result += '\n';
	}

	return result;
}

u64 int_program_live_outs(const int_program* program) {
	u64 touched = 0;
	u64 live_out = 0;

	for(u64 idx = program->size; idx-- > 0;) {
		const int_inst& in = program->instructions[idx];
		const int_inst_spec* spec = int_find_spec(in.op);

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
