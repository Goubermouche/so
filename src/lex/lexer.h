#ifndef LEX_LEXER_H
#define LEX_LEXER_H

#include "utl/str.h"

typedef enum lex_token {
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
	TOK_EOF,
} lex_token;

typedef struct lex_lexer {
	str source;
	char current_char;
	u64 index;
	lex_token curr;
	str curr_string;
	i64 curr_imm; // signed
} lex_lexer;

lex_lexer lex_make(str source);
lex_token lex_next_tok(lex_lexer* lex);
lex_token lex_next_tok_identifier(lex_lexer* lex);
lex_token lex_next_tok_comment(lex_lexer* lex);
lex_token lex_next_tok_string(lex_lexer* lex);
lex_token lex_next_tok_char(lex_lexer* lex);

char lex_next_char(lex_lexer* lex);
b32 lex_is_at_end(lex_lexer* lex);
void lex_consume_spaces(lex_lexer* lex);
b32 lex_is_whitespace(char c);

lex_token lex_str_to_tok(str string);
lex_token lex_str_to_num(lex_lexer* lex, str string);

const char* lex_token_to_str(lex_token tok);
b32 lex_token_is_reg(lex_token tok);
u64 lex_token_to_reg_index(lex_token tok);

#endif // LEX_LEXER_H
