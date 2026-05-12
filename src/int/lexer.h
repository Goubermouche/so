#ifndef INT_LEXER_H
#define INT_LEXER_H

#include "utl/str.h"

typedef enum int_token {
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
} int_token;

typedef struct int_lexer {
	str source;
	char current_char;
	u64 index;
	int_token curr;
	str curr_string;
	i64 curr_imm; // signed
} int_lexer;

int_lexer int_lexer_make(str source);
int_token int_lexer_next_tok(int_lexer* lex);
int_token int_lexer_next_tok_identifier(int_lexer* lex);
int_token int_lexer_next_tok_comment(int_lexer* lex);
int_token int_lexer_next_tok_string(int_lexer* lex);
int_token int_lexer_next_tok_char(int_lexer* lex);

char int_lexer_next_char(int_lexer* lex);
b32 int_lexer_is_at_end(int_lexer* lex);
void int_lexer_consume_spaces(int_lexer* lex);
b32 int_lexer_is_whitespace(char c);

int_token int_lexer_string_to_tok(str string);
int_token int_lexer_string_to_num(int_lexer* lex, str string);

const char* int_token_to_str(int_token tok);
b32 int_token_is_reg(int_token tok);
u64 int_token_to_reg_index(int_token tok);

#endif // INT_LEXER_H
