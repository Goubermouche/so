#include "parser.h"
#include "assembler/tokenizer.h"

namespace so {
	auto parser::parse(const str &source) -> arr<inst> {
		arr<inst> result;
		tokenizer tok(source);
		str curr_name;

		tok.next_char();
		tok.next_tok();

		while(tok.curr != token::TOK_EOF) {
			// leading empty lines
			while(tok.curr == TOK_NEWLINE) {
				tok.next_tok();
			}

			// mnemonic
			inst curr_inst;
			inst_op operands[4] = {};
			u8 operand_count = 0;

			curr_name = tok.curr_string;
			tok.next_tok();

			// operands
			while(tok.curr != TOK_NEWLINE && operand_count < 2) {
				if(token_is_reg(tok.curr)) {
					curr_inst.ops[operand_count].r = token_to_reg_index(tok.curr);
					operands[operand_count] = OP_R;
				}
				else if(tok.curr == TOK_NUMBER) {
					curr_inst.ops[operand_count].i = tok.curr_imm;
					operands[operand_count] = OP_I;
				}
				else {
					ASSERT(false, "unrecognized operand type received");
				}

	 			operand_count++;

				if(tok.next_tok() != TOK_COMMA) {
					break;
				}
				else {
					tok.next_tok();
				}
			}

			curr_inst.tag = find_inst_tag(curr_name, operands, operand_count);

			ASSERT(tok.curr == TOK_NEWLINE, "expected newline");
			result.push_back(curr_inst);
			tok.next_tok(); // consume newline
		}

		return result;
	}
} // namespace so

