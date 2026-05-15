#include "cpu/program.h"
#include "lexer/lexer.h"

cpu_program cpu_program_parse(str source) {
	arena tmp = arena_make(0);
	cpu_inst_arr result = cpu_inst_arr_make(&tmp);
	lex_lexer lex = lex_make(source);
	lex_next_char(&lex);
	lex_next_tok(&lex);

	while(lex.curr != TOK_EOF) {
		// skip leading blank lines between instructions
		while(lex.curr == TOK_NEWLINE) lex_next_tok(&lex);
		if(lex.curr == TOK_EOF) break;

		if(lex.curr == TOK_IDENTIFIER) {
			str saved = lex.curr_string;
			lex_next_tok(&lex);
			if(lex.curr == TOK_COLON) {
				lex_next_tok(&lex);
				if(lex.curr == TOK_NEWLINE) lex_next_tok(&lex);
				continue;
			}
			// not a label after all - rewind by re-parsing as a mnemonic
			cpu_inst curr_inst = {};
			cpu_inst_spec::operand operand_types[4] = {};
			u8 operand_count = 0;

			while(lex.curr != TOK_NEWLINE && lex.curr != TOK_EOF && operand_count < 4) {
				if(lex_token_is_reg(lex.curr)) {
					curr_inst.operands[operand_count].reg = (cpu_reg_index)(lex_token_to_reg_index(lex.curr));
					operand_types[operand_count] = cpu_inst_spec::REG;
				} else if(lex.curr == TOK_NUMBER) {
					curr_inst.operands[operand_count].i = (u64)lex.curr_imm;
					operand_types[operand_count] = cpu_inst_spec::IMM;
				} else if(lex.curr == TOK_MINUS) {
					lex_next_tok(&lex);
					ASSERT(lex.curr == TOK_NUMBER, "expected number after '-'");
					curr_inst.operands[operand_count].i = (u64)(-lex.curr_imm);
					operand_types[operand_count] = cpu_inst_spec::IMM;
				} else {
					ASSERT(false, "unrecognized operand type received ('%s')", lex_token_to_str(lex.curr));
				}

				operand_count++;

				if(lex_next_tok(&lex) != TOK_COMMA) break;
				lex_next_tok(&lex);
			}

			// pseudo-op rewriting
			//   sext.w rd, rs1   ->   addiw rd, rs1, 0
			if(str_eq_cstr(saved, "sext.w") && operand_count == 2 &&
				 operand_types[0] == cpu_inst_spec::REG && operand_types[1] == cpu_inst_spec::REG) {
				saved = STR_LIT("addiw");
				curr_inst.operands[2].i = 0;
				operand_types[2] = cpu_inst_spec::IMM;
				operand_count = 3;
			}

			curr_inst.op = cpu_find_inst_op(saved, operand_types, operand_count);
			ASSERT(curr_inst.op != OP_COUNT, "no opcode matches mnemonic '%.*s' with %d operand(s)\n",
						 (int)saved.size, (const char*)saved.str, (int)operand_count);
			cpu_inst_arr_push(&result, curr_inst);

			if(lex.curr == TOK_NEWLINE) { lex_next_tok(&lex); }
			continue;
		}

		ASSERT(false, "expected mnemonic, got '%s'", lex_token_to_str(lex.curr));
	}

	cpu_inst* data = (cpu_inst*)malloc(sizeof(cpu_inst) * result.size);
	memcpy(data, result.v, sizeof(cpu_inst) * result.size);
	cpu_program out = {data, (u32)result.size};
	arena_release(&tmp);
	return out;
}

void cpu_program_free(const cpu_program* program) { free(program->instructions); }

cpu_program cpu_program_dce(const cpu_program* program, u64 live_mask) {
	// x0 is never live in the user-facing sense (writes are dropped)
	u64 live = live_mask & ~1ULL;
	u64 live_bits_by_slot = 0;
	u32 count = 0;

	for(i32 i = (i32)program->size - 1; i >= 0; --i) {
		const cpu_inst_spec* spec = cpu_find_spec(program->instructions[i].op);

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

	cpu_program out;
	out.size = 0;
	for(u32 i = 0; i < program->size; ++i) {
		if(live_bits_by_slot & (1ULL << i)) { out.size++; }
	}
	out.instructions = (cpu_inst*)malloc(sizeof(cpu_inst) * out.size);
	u32 index = 0;
	for(u32 i = 0; i < program->size; ++i) {
		if(live_bits_by_slot & (1ULL << i)) { out.instructions[index++] = program->instructions[i]; }
	}

	return out;
}

str cpu_program_to_str(arena* a, const cpu_program* program) {
	str_list builder = {};

	for(u32 i = 0; i < program->size; ++i) {
		const cpu_inst inst = program->instructions[i];
		const cpu_inst_spec* spec = cpu_find_spec(inst.op);
		str_list_push(a, &builder, STR_LIT("    "));
		str_list_push(a, &builder, str_pad_to_len(a, str_cstring(spec->name), ' ', 8));

		const u8 nop = cpu_spec_get_operand_count(spec);
		for(u8 j = 0; j < nop; ++j) {
			str_list_push(a, &builder, cpu_operand_to_string(a, inst.operands[j], spec->operands[j]));
			if(j + 1 < nop) { str_list_push(a, &builder, STR_LIT(", ")); }
		}

		str_list_push(a, &builder, STR_LIT("\n"));
	}

	return str_list_flatten(a, &builder, STR_LIT(""));
}

u64 cpu_program_live_outs(const cpu_program* program) {
	u64 touched = 0;
	u64 live_out = 0;

	for(u64 idx = program->size; idx-- > 0;) {
		const cpu_inst& in = program->instructions[idx];
		const cpu_inst_spec* spec = cpu_find_spec(in.op);

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
