#include "parser.h"

namespace so {
	auto parser::parse(const str &source) -> arr<inst> {
		tokenizer tok(source);
		tok.next_char();
		tok.next_tok();
		int i = 0 ;

		while(tok.curr != token::TOK_EOF && i < 30) {
			print("{}\n", token_to_str(tok.curr));
			tok.next_tok();
			i++;
		}

		return {};
	}
} // namespace so

