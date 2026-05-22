#ifndef LEX_LEXER_H
#define LEX_LEXER_H

#include "util/string.h"

typedef enum LexerToken {
	LexerToken_Unknown = 0,

	LexerToken_Identifier,
	LexerToken_Number,

	// regs
	LexerToken_RegX0,
	LexerToken_RegX1,
	LexerToken_RegX2,
	LexerToken_RegX3,
	LexerToken_RegX4,
	LexerToken_RegX5,
	LexerToken_RegX6,
	LexerToken_RegX7,
	LexerToken_RegX8,
	LexerToken_RegX9,
	LexerToken_RegX10,
	LexerToken_RegX11,
	LexerToken_RegX12,
	LexerToken_RegX13,
	LexerToken_RegX14,
	LexerToken_RegX15,
	LexerToken_RegX16,
	LexerToken_RegX17,
	LexerToken_RegX18,
	LexerToken_RegX19,
	LexerToken_RegX20,
	LexerToken_RegX21,
	LexerToken_RegX22,
	LexerToken_RegX23,
	LexerToken_RegX24,
	LexerToken_RegX25,
	LexerToken_RegX26,
	LexerToken_RegX27,
	LexerToken_RegX28,
	LexerToken_RegX29,
	LexerToken_RegX30,
	LexerToken_RegX31,

	// other
	LexerToken_Comma,
	LexerToken_LeftBracket,
	LexerToken_RightBracket,
	LexerToken_LeftBrace,
	LexerToken_RightBrace,
	LexerToken_Plus,
	LexerToken_Minus,
	LexerToken_Asterisk,
	LexerToken_DollarSign,
	LexerToken_Colon,
	LexerToken_Newline,
	LexerToken_EndOfFile,
} LexerToken;

typedef struct Lexer {
	string source;
	C8 current_char;
	U64 index;
	LexerToken curr;
	string curr_string;
	I64 curr_imm; // signed
} Lexer;

I32 lexer_make(Lexer* lexer, string source);

LexerToken lexer_next_tok(Lexer* lexer);
LexerToken lexer_next_tok_identifier(Lexer* lexer);
LexerToken lexer_next_tok_comment(Lexer* lexer);
LexerToken lexer_next_tok_string(Lexer* lexer);
LexerToken lexer_next_tok_char(Lexer* lexer);

C8   lexer_next_char(Lexer* lexer);
B32  lexer_is_at_end(Lexer* lexer);
void lexer_consume_spaces(Lexer* lexer);
B32  lexer_is_whitespace(C8 c);

LexerToken lexer_str_to_tok(string string);
LexerToken lexer_str_to_num_tok(Lexer* lexer, string string);

string lexer_token_to_str(LexerToken tok);
B32    lexer_token_is_reg(LexerToken tok);
U64    lexer_token_to_reg_index(LexerToken tok);

#endif // LEX_LEXER_H
