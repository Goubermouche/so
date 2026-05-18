#ifndef LEX_LEXER_H
#define LEX_LEXER_H

#include "util/string.h"

namespace sup {
enum class token {
	UNKNOWN = 0,

	IDENTIFIER,
	NUMBER,

	// regs
	REG_X0,
	REG_X1,
	REG_X2,
	REG_X3,
	REG_X4,
	REG_X5,
	REG_X6,
	REG_X7,
	REG_X8,
	REG_X9,
	REG_X10,
	REG_X11,
	REG_X12,
	REG_X13,
	REG_X14,
	REG_X15,
	REG_X16,
	REG_X17,
	REG_X18,
	REG_X19,
	REG_X20,
	REG_X21,
	REG_X22,
	REG_X23,
	REG_X24,
	REG_X25,
	REG_X26,
	REG_X27,
	REG_X28,
	REG_X29,
	REG_X30,
	REG_X31,

	// other
	COMMA,
	LBRACKET,
	RBRACKET,
	LBRACE,
	RBRACE,
	PLUS,
	MINUS,
	ASTERISK,
	DOLLARSIGN,
	COLON,
	NEWLINE,
	END_OF_FILE,
};

struct lexer {
	string source;
	c8 current_char;
	u64 index;
	token curr;
	string curr_string;
	i64 curr_imm; // signed
};

lexer lex_make(string source);
token lex_next_tok(lexer* lex);
token lex_next_tok_identifier(lexer* lex);
token lex_next_tok_comment(lexer* lex);
token lex_next_tok_string(lexer* lex);
token lex_next_tok_char(lexer* lex);

c8 lex_next_char(lexer* lex);
b32 lex_is_at_end(lexer* lex);
void lex_consume_spaces(lexer* lex);
b32 lex_is_whitespace(c8 c);

token lex_str_to_tok(string string);
token lex_str_to_num(lexer* lex, string string);

const c8* lex_token_to_str(token tok);
b32 lex_token_is_reg(token tok);
u64 lex_token_to_reg_index(token tok);
} // namespace sup

#endif // LEX_LEXER_H
