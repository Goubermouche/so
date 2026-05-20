#include "cpu/program.h"
#include "lexer/lexer.h"

namespace sup {

program program::parse(arena& a, string source) {
	array<Instruction> result;
	Lexer lex;
	lexer_make(&lex, source);
	lexer_next_char(&lex);
	lexer_next_tok(&lex);

	while(lex.curr != TOK_END_OF_FILE) {
		// skip leading blank lines between instructions
		while(lex.curr == TOK_NEWLINE) lexer_next_tok(&lex);
		if(lex.curr == TOK_END_OF_FILE) break;

		if(lex.curr == TOK_IDENTIFIER) {
			string saved = lex.curr_string;
			lexer_next_tok(&lex);
			if(lex.curr == TOK_COLON) {
				lexer_next_tok(&lex);
				if(lex.curr == TOK_NEWLINE) lexer_next_tok(&lex);
				continue;
			}
			// not a label after all - rewind by re-parsing as a mnemonic
			Instruction curr_inst = {};
			InstructionOperandType operand_types[4] = {};
			u8 operand_count = 0;

			while(lex.curr != TOK_NEWLINE && lex.curr != TOK_END_OF_FILE &&
						operand_count < 4) {
				if(lexer_token_is_reg(lex.curr)) {
					curr_inst.operands[operand_count].reg =
						(Reg)(lexer_token_to_reg_index(lex.curr));
					operand_types[operand_count] = InstructionOperandType_Reg;
				} else if(lex.curr == TOK_NUMBER) {
					curr_inst.operands[operand_count].imm = (u64)lex.curr_imm;
					operand_types[operand_count] = InstructionOperandType_Imm;
				} else if(lex.curr == TOK_MINUS) {
					lexer_next_tok(&lex);
					ASSERT(lex.curr == TOK_NUMBER, "expected number after '-'");
					curr_inst.operands[operand_count].imm = (u64)(-lex.curr_imm);
					operand_types[operand_count] = InstructionOperandType_Imm;
				} else {
					ASSERT(false, "unrecognized operand type received ('%s')",
								 lexer_token_to_str(lex.curr).ptr);
				}

				operand_count++;

				if(lexer_next_tok(&lex) != TOK_COMMA) break;
				lexer_next_tok(&lex);
			}

			// pseudo-op rewriting
			//   sext.w rd, rs1   ->   addiw rd, rs1, 0
			if(saved == "sext.w" && operand_count == 2 &&
				 operand_types[0] == InstructionOperandType_Reg && operand_types[1] == InstructionOperandType_Reg) {
				saved = "addiw";
				curr_inst.operands[2].imm = 0;
				operand_types[2] = InstructionOperandType_Imm;
				operand_count = 3;
			}

			curr_inst.op = instruction_db_find(saved, operand_types, operand_count);
			ASSERT(curr_inst.op != InstructionOpcode_Count,
						 "no InstructionOpcode matches mnemonic '%.*s' with %d operand(s)\n",
						 (int)saved.size, (const c8*)saved.ptr, (int)operand_count);
			result.push(curr_inst);

			if(lex.curr == TOK_NEWLINE) { lexer_next_tok(&lex); }
			continue;
		}

		ASSERT(false, "expected mnemonic, got '%s'", lexer_token_to_str(lex.curr).ptr);
	}

	Instruction* data = a.push<Instruction>(result.size);
	memcpy(data, result.ptr, sizeof(Instruction) * result.size);
	program out = {data, result.size};
	return out;
}

string program::to_string(arena& a) const {
	array<string> builder;

	for(u32 i = 0; i < size; ++i) {
		const Instruction Instruction = ptr[i];
		const InstructionInfo* info = instruction_db_find_info(Instruction.op);
		builder.push("  ");
		string inst_name = string(info->name);
		inst_name.pad(a, ' ', 8);
		builder.push(inst_name);

		const u8 nop = info->operand_count;
		for(u8 j = 0; j < nop; ++j) {
			builder.push(operand_to_string(a, Instruction.operands[j], info->operands[j]));
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
		const Instruction& in = ptr[idx];
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

u64 program::get_live_in() const {
	u64 written = 0;
	u64 live_in = 0;

	for(u32 i = 0; i < size; ++i) {
		const InstructionInfo* info = instruction_db_find_info(ptr[i].op);

		if(info->src_slot >= 0) {
			const u32 r = (u32)ptr[i].operands[info->src_slot].reg;
			if(!(written & (1ull << r))) { live_in |= 1ull << r; }
		}

		if(info->src2_slot >= 0) {
			const u32 r = (u32)ptr[i].operands[info->src2_slot].reg;
			if(!(written & (1ull << r))) { live_in |= 1ull << r; }
		}

		if(info->dst_slot >= 0) {
			const u32 r = (u32)ptr[i].operands[info->dst_slot].reg;
			written |= 1ull << r;
		}
	}

	return live_in & ~1ull; // remove x0
}
} // namespace sup