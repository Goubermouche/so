#include "cpu/program.h"
#include "lexer/lexer.h"

I32 program_parse(Program* Program, Arena* a, S8 source) {
	Instruction buf[MaxProgramLen];
	U32 count = 0;
	Lexer lexer;
	lexer_make(&lexer, source);
	lexer_next_char(&lexer);
	lexer_next_tok(&lexer);

	while(lexer.curr != LexerToken_EndOfFile) {
		// skip leading blank lines between instructions
		while(lexer.curr == LexerToken_Newline) lexer_next_tok(&lexer);
		if(lexer.curr == LexerToken_EndOfFile) break;

		if(lexer.curr == LexerToken_Identifier) {
			S8 saved = lexer.curr_string;
			lexer_next_tok(&lexer);
			if(lexer.curr == LexerToken_Colon) {
				lexer_next_tok(&lexer);
				if(lexer.curr == LexerToken_Newline) lexer_next_tok(&lexer);
				continue;
			}

			// not a label after all - parse as a mnemonic
			Instruction curr_inst = {};
			InstructionOperandType operand_types[4] = {};
			U8 operand_count = 0;

			while(lexer.curr != LexerToken_Newline && lexer.curr != LexerToken_EndOfFile &&
						operand_count < 4) {
				if(lexer_token_is_reg(lexer.curr)) {
					curr_inst.operands[operand_count].reg = (Reg)(lexer_token_to_reg_index(lexer.curr));
					operand_types[operand_count] = InstructionOperandType_Reg;
				} else if(lexer.curr == LexerToken_Number) {
					curr_inst.operands[operand_count].imm = (U64)lexer.curr_imm;
					operand_types[operand_count] = InstructionOperandType_Imm;
				} else if(lexer.curr == LexerToken_Minus) {
					lexer_next_tok(&lexer);
					Assert(lexer.curr == LexerToken_Number, "expected number after '-'");
					curr_inst.operands[operand_count].imm = (U64)(-lexer.curr_imm);
					operand_types[operand_count] = InstructionOperandType_Imm;
				} else {
					Assert(false, "unrecognized operand type received ('%s')",
								 lexer_token_to_str(lexer.curr).ptr);
				}

				operand_count++;

				if(lexer_next_tok(&lexer) != LexerToken_Comma) break;
				lexer_next_tok(&lexer);
			}

			// pseudo-op rewriting
			//   sext.w rd, rs1   ->   addiw rd, rs1, 0
			if(str_match_cstr(saved, "sext.w") && operand_count == 2 &&
				 operand_types[0] == InstructionOperandType_Reg &&
				 operand_types[1] == InstructionOperandType_Reg) {
				saved = S8("addiw");
				curr_inst.operands[2].imm = 0;
				operand_types[2] = InstructionOperandType_Imm;
				operand_count = 3;
			}

			curr_inst.op = instruction_db_find(saved, operand_types, operand_count);
			Assert(curr_inst.op != InstructionOpcode_Count,
						 "no InstructionOpcode matches mnemonic '%.*s' with %d operand(s)\n", (int)saved.size,
						 saved.ptr, (int)operand_count);

			if(count >= MaxProgramLen) {
				fprintf(stderr, "error: program_parse: source exceeds MaxProgramLen (%d) instructions\n",
								MaxProgramLen);
				return 1;
			}
			buf[count++] = curr_inst;

			if(lexer.curr == LexerToken_Newline) { lexer_next_tok(&lexer); }
			continue;
		}

		Assert(false, "expected mnemonic, got '%s'", lexer_token_to_str(lexer.curr).ptr);
	}

	Instruction* data = ArenaPush(a, Instruction, count);
	memcpy(data, buf, sizeof(Instruction) * count);
	Program->instructions = data;
	Program->size = count;
	return 0;
}

S8 program_to_string(Program* Program, Arena* a) {
	Arena* scratch = arena_make(0);
	C8* start = (C8*)ArenaPush(a, C8, 0);
	U64 total = 0;

	for(U32 i = 0; i < Program->size; ++i) {
		Instruction inst = Program->instructions[i];
		InstructionInfo* info = instruction_db_find_info(inst.op);
		arena_push_data(a, "  ", 2);
		total += 2;

		U64 name_len = info->name.size;
		arena_push_data(a, info->name.ptr, name_len);
		total += name_len;
		if(name_len < 8) {
			C8 pad[8] = {' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '};
			arena_push_data(a, pad, 8 - name_len);
			total += 8 - name_len;
		}

		U8 nop = info->operand_count;
		for(U8 j = 0; j < nop; ++j) {
			S8 s = operand_to_string(scratch, inst.operands[j], info->operands[j]);
			arena_push_data(a, s.ptr, s.size);
			total += s.size;
			if(j + 1 < nop) {
				arena_push_data(a, ", ", 2);
				total += 2;
			}
		}

		arena_push_data(a, "\n", 1);
		total += 1;
	}

	arena_free(scratch);
	S8 r = str_make(start, total);
	return r;
}

U64 program_get_live_out(Program* Program) {
	U64 touched = 0;
	U64 live_out = 0;

	for(U64 idx = Program->size; idx-- > 0;) {
		Instruction& in = Program->instructions[idx];
		InstructionInfo* info = instruction_db_find_info(in.op);

		// write side first
		if(info->dst_slot >= 0) {
			U32 r = (U32)in.operands[info->dst_slot].reg;

			// x0 writes don't define anything
			if(r != 0) {
				U64 bit = 1ULL << r;

				if(!(touched & bit)) {
					live_out |= bit;
					touched |= bit;
				}
			}
		}

		// read side
		if(info->src_slot >= 0) {
			U32 r = (U32)in.operands[info->src_slot].reg;
			touched |= 1ULL << r;
		}

		if(info->src2_slot >= 0) {
			U32 r = (U32)in.operands[info->src2_slot].reg;
			touched |= 1ULL << r;
		}
	}

	return live_out;
}

U64 program_get_live_in(Program* Program) {
	U64 written = 0;
	U64 live_in = 0;

	for(U32 i = 0; i < Program->size; ++i) {
		InstructionInfo* info = instruction_db_find_info(Program->instructions[i].op);

		if(info->src_slot >= 0) {
			U32 r = (U32)Program->instructions[i].operands[info->src_slot].reg;
			if(!(written & (1ull << r))) { live_in |= 1ull << r; }
		}

		if(info->src2_slot >= 0) {
			U32 r = (U32)Program->instructions[i].operands[info->src2_slot].reg;
			if(!(written & (1ull << r))) { live_in |= 1ull << r; }
		}

		if(info->dst_slot >= 0) {
			U32 r = (U32)Program->instructions[i].operands[info->dst_slot].reg;
			written |= 1ull << r;
		}
	}

	return live_in & ~1ull; // remove x0
}