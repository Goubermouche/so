#ifndef LEX_LEXER_H
#define LEX_LEXER_H

#include "util/string.h"

namespace sup {
typedef enum LexerToken {
	TOK_UNKNOWN = 0,

	TOK_IDENTIFIER,
	TOK_NUMBER,

	// regs
	TOK_REG_X0,
	TOK_REG_X1,
	TOK_REG_X2,
	TOK_REG_X3,
	TOK_REG_X4,
	TOK_REG_X5,
	TOK_REG_X6,
	TOK_REG_X7,
	TOK_REG_X8,
	TOK_REG_X9,
	TOK_REG_X10,
	TOK_REG_X11,
	TOK_REG_X12,
	TOK_REG_X13,
	TOK_REG_X14,
	TOK_REG_X15,
	TOK_REG_X16,
	TOK_REG_X17,
	TOK_REG_X18,
	TOK_REG_X19,
	TOK_REG_X20,
	TOK_REG_X21,
	TOK_REG_X22,
	TOK_REG_X23,
	TOK_REG_X24,
	TOK_REG_X25,
	TOK_REG_X26,
	TOK_REG_X27,
	TOK_REG_X28,
	TOK_REG_X29,
	TOK_REG_X30,
	TOK_REG_X31,

	// other
	TOK_COMMA,
	TOK_LBRACKET,
	TOK_RBRACKET,
	TOK_LBRACE,
	TOK_RBRACE,
	TOK_PLUS,
	TOK_MINUS,
	TOK_ASTERISK,
	TOK_DOLLARSIGN,
	TOK_COLON,
	TOK_NEWLINE,
	TOK_END_OF_FILE,
} LexerToken;

struct Lexer {
	string source;
	c8 current_char;
	u64 index;
	LexerToken curr;
	string curr_string;
	i64 curr_imm; // signed
};

i32 lexer_make(Lexer* lexer, string source);

LexerToken lexer_next_tok(Lexer* lex);
LexerToken lexer_next_tok_identifier(Lexer* lex);
LexerToken lexer_next_tok_comment(Lexer* lex);
LexerToken lexer_next_tok_string(Lexer* lex);
LexerToken lexer_next_tok_char(Lexer* lex);

c8   lexer_next_char(Lexer* lex);
b32  lexer_is_at_end(Lexer* lex);
void lexer_consume_spaces(Lexer* lex);
b32  lexer_is_whitespace(c8 c);

LexerToken lexer_str_to_tok(string string);
LexerToken lexer_str_to_num_tok(Lexer* lex, string string);

string lexer_token_to_str(LexerToken tok);
b32    lexer_token_is_reg(LexerToken tok);
u64    lexer_token_to_reg_index(LexerToken tok);
} // namespace sup

#endif // LEX_LEXER_H
