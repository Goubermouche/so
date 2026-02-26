#include "parser.h"
#include "assembler/instruction.h"
#include "assembler/tokenizer.h"

namespace so {
	auto parser::parse(const str &source) -> arr<inst> {
		arr<inst> result;
		tokenizer tok(source);
		tok.next_char();
		tok.next_tok();

		while(tok.curr != token::TOK_EOF) {
			// leading empty lines
			while(tok.curr == TOK_NEWLINE) {
				tok.next_tok();
			}

			// mnemonic
			inst curr_inst;
			curr_inst.operand_count = 0;
			curr_inst.op = identifier_to_opcode(tok.curr_string);
			ASSERT(curr_inst.op != OP_NONE, "invalid instruction name ({})", token_to_str(tok.curr));
			tok.next_tok();

			// operands
			while(tok.curr != TOK_NEWLINE && curr_inst.operand_count < 2) {
				operand curr_op;

				if(token_is_reg(tok.curr)) {
					curr_op = operand::make_reg(token_to_reg_index(tok.curr));
				}
				else if(tok.curr == TOK_NUMBER) {
					curr_op = operand::make_imm(tok.curr_imm);
				}
				else {
					ASSERT(false, "unrecognized operand type received");
				}

				curr_inst.operands[curr_inst.operand_count++] = curr_op;

				if(tok.next_tok() != TOK_COMMA) {
					break;
				}
				else {
					tok.next_tok();
				}
			}

			ASSERT(tok.curr == TOK_NEWLINE, "expected newline");
			result.push_back(curr_inst);
			tok.next_tok(); // consume newline
		}

		return result;
	}

	auto parser::identifier_to_opcode(const str& ident) -> opcode {
		static const map<str, opcode> opcode_map = {
			{ "mov", OP_MOV },
			{ "sub", OP_SUB },
			{ "not", OP_NOT },
			{ "and", OP_AND },
			{ "neg", OP_NEG }
		};

		const auto it = opcode_map.find(ident);
		if(it == opcode_map.end()) {
			return OP_NONE;
		}
		return it->second;
	}
} // namespace so

