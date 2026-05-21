#include "cpu/program.h"
#include "lexer/lexer.h"

i32 program_parse(Program* Program, arena* a, string source) {
	array<Instruction> result;
	Lexer lexer;
	lexer_make(&lexer, source);
	lexer_next_char(&lexer);
	lexer_next_tok(&lexer);

	while(lexer.curr != LexerToken_EndOfFile) {
		// skip leading blank lines between instructions
		while(lexer.curr == LexerToken_Newline) lexer_next_tok(&lexer);
		if(lexer.curr == LexerToken_EndOfFile) break;

		if(lexer.curr == LexerToken_Identifier) {
			string saved = lexer.curr_string;
			lexer_next_tok(&lexer);
			if(lexer.curr == LexerToken_Colon) {
				lexer_next_tok(&lexer);
				if(lexer.curr == LexerToken_Newline) lexer_next_tok(&lexer);
				continue;
			}
			// not a label after all - rewind by re-parsing as a mnemonic
			Instruction curr_inst = {};
			InstructionOperandType operand_types[4] = {};
			u8 operand_count = 0;

			while(lexer.curr != LexerToken_Newline && lexer.curr != LexerToken_EndOfFile &&
						operand_count < 4) {
				if(lexer_token_is_reg(lexer.curr)) {
					curr_inst.operands[operand_count].reg = (Reg)(lexer_token_to_reg_index(lexer.curr));
					operand_types[operand_count] = InstructionOperandType_Reg;
				} else if(lexer.curr == LexerToken_Number) {
					curr_inst.operands[operand_count].imm = (u64)lexer.curr_imm;
					operand_types[operand_count] = InstructionOperandType_Imm;
				} else if(lexer.curr == LexerToken_Minus) {
					lexer_next_tok(&lexer);
					ASSERT(lexer.curr == LexerToken_Number, "expected number after '-'");
					curr_inst.operands[operand_count].imm = (u64)(-lexer.curr_imm);
					operand_types[operand_count] = InstructionOperandType_Imm;
				} else {
					ASSERT(false, "unrecognized operand type received ('%s')",
								 lexer_token_to_str(lexer.curr).ptr);
				}

				operand_count++;

				if(lexer_next_tok(&lexer) != LexerToken_Comma) break;
				lexer_next_tok(&lexer);
			}

			// pseudo-op rewriting
			//   sext.w rd, rs1   ->   addiw rd, rs1, 0
			if(saved == "sext.w" && operand_count == 2 &&
				 operand_types[0] == InstructionOperandType_Reg &&
				 operand_types[1] == InstructionOperandType_Reg) {
				saved = "addiw";
				curr_inst.operands[2].imm = 0;
				operand_types[2] = InstructionOperandType_Imm;
				operand_count = 3;
			}

			curr_inst.op = instruction_db_find(saved, operand_types, operand_count);
			ASSERT(curr_inst.op != InstructionOpcode_Count,
						 "no InstructionOpcode matches mnemonic '%.*s' with %d operand(s)\n", (int)saved.size,
						 (const c8*)saved.ptr, (int)operand_count);
			result.push(curr_inst);

			if(lexer.curr == LexerToken_Newline) { lexer_next_tok(&lexer); }
			continue;
		}

		ASSERT(false, "expected mnemonic, got '%s'", lexer_token_to_str(lexer.curr).ptr);
	}

	Instruction* data = a->push<Instruction>(result.size);
	memcpy(data, result.ptr, sizeof(Instruction) * result.size);
	Program->instructions = data;
	Program->size = result.size;
	return 0;
}

string program_to_string(Program* Program, arena* a) {
	array<string> builder;

	for(u32 i = 0; i < Program->size; ++i) {
		const Instruction Instruction = Program->instructions[i];
		const InstructionInfo* info = instruction_db_find_info(Instruction.op);
		builder.push("  ");
		string inst_name = string(info->name);
		inst_name.pad(*a, ' ', 8);
		builder.push(inst_name);

		const u8 nop = info->operand_count;
		for(u8 j = 0; j < nop; ++j) {
			builder.push(operand_to_string(*a, Instruction.operands[j], info->operands[j]));
			if(j + 1 < nop) { builder.push(", "); }
		}

		builder.push("\n");
	}

	return str_list_flatten(*a, builder, "");
}

u64 program_get_live_out(Program* Program) {
	u64 touched = 0;
	u64 live_out = 0;

	for(u64 idx = Program->size; idx-- > 0;) {
		const Instruction& in = Program->instructions[idx];
		const InstructionInfo* info = instruction_db_find_info(in.op);

		// write side first
		if(info->dst_slot >= 0) {
			const u32 r = (u32)in.operands[info->dst_slot].reg;

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
		if(info->src_slot >= 0) {
			const u32 r = (u32)in.operands[info->src_slot].reg;
			touched |= 1ULL << r;
		}

		if(info->src2_slot >= 0) {
			const u32 r = (u32)in.operands[info->src2_slot].reg;
			touched |= 1ULL << r;
		}
	}

	return live_out;
}

u64 program_get_live_in(Program* Program) {
	u64 written = 0;
	u64 live_in = 0;

	for(u32 i = 0; i < Program->size; ++i) {
		const InstructionInfo* info = instruction_db_find_info(Program->instructions[i].op);

		if(info->src_slot >= 0) {
			const u32 r = (u32)Program->instructions[i].operands[info->src_slot].reg;
			if(!(written & (1ull << r))) { live_in |= 1ull << r; }
		}

		if(info->src2_slot >= 0) {
			const u32 r = (u32)Program->instructions[i].operands[info->src2_slot].reg;
			if(!(written & (1ull << r))) { live_in |= 1ull << r; }
		}

		if(info->dst_slot >= 0) {
			const u32 r = (u32)Program->instructions[i].operands[info->dst_slot].reg;
			written |= 1ull << r;
		}
	}

	return live_in & ~1ull; // remove x0
}