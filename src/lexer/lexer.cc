#include "lexer/lexer.h"
#include "cpu/cpu.cuh"

Str lexer_token_to_str(LexerToken tok) {
	switch(tok) {
		case LexerToken_Unknown: return StrLit("unknown");
		case LexerToken_Identifier: return StrLit("identifier");
		case LexerToken_Number: return StrLit("number");
		case LexerToken_Comma: return StrLit(",");
		case LexerToken_LeftBracket: return StrLit("[");
		case LexerToken_RightBracket: return StrLit("]");
		case LexerToken_LeftBrace: return StrLit("(");
		case LexerToken_RightBrace: return StrLit(")");
		case LexerToken_Plus: return StrLit("+");
		case LexerToken_Minus: return StrLit("-");
		case LexerToken_Asterisk: return StrLit("*");
		case LexerToken_DollarSign: return StrLit("$");
		case LexerToken_Colon: return StrLit(":");
		case LexerToken_Newline: return StrLit("newline");
		case LexerToken_EndOfFile: return StrLit("eof");
		default:
			if(lexer_token_is_reg(tok)) {
				return reg_name(lexer_token_to_reg_index(tok));
			}
			return StrLit("?");
	}
}

B32 lexer_token_is_reg(LexerToken tok) {
	return tok >= LexerToken_RegX0 && tok <= LexerToken_RegX31;
}

U64 lexer_token_to_reg_index(LexerToken tok) {
	Assert(lexer_token_is_reg(tok), "LexerToken is not a register");
	return (U64)tok - (U64)LexerToken_RegX0;
}

I32 lexer_make(Lexer* lexer, Str source) {
	lexer->index = 0;
	lexer->source = source;
	lexer->current_char = 0;
	lexer->curr = LexerToken_Unknown;
	lexer->curr_imm = 0;
	return 0;
}

LexerToken lexer_next_tok(Lexer* lexer) {
	lexer->curr_string = {};

	// get rid of leading space-like characters
	lexer_consume_spaces(lexer);

	// special characters
	switch(lexer->current_char) {
		case '_':
		case '.':
		case '0' ... '9':
		case 'a' ... 'z':
		case 'A' ... 'Z': return lexer_next_tok_identifier(lexer);

		case ';':
		case '#': return lexer_next_tok_comment(lexer);
		case '"': return lexer_next_tok_string(lexer);
		case '\'': return lexer_next_tok_char(lexer);

		case ',': lexer_next_char(lexer); return lexer->curr = LexerToken_Comma;
		case '[': lexer_next_char(lexer); return lexer->curr = LexerToken_LeftBracket;
		case ']': lexer_next_char(lexer); return lexer->curr = LexerToken_RightBracket;
		case '(': lexer_next_char(lexer); return lexer->curr = LexerToken_LeftBrace;
		case ')': lexer_next_char(lexer); return lexer->curr = LexerToken_RightBrace;
		case '+': lexer_next_char(lexer); return lexer->curr = LexerToken_Plus;
		case '-': lexer_next_char(lexer); return lexer->curr = LexerToken_Minus;
		case '*': lexer_next_char(lexer); return lexer->curr = LexerToken_Asterisk;
		case '$': lexer_next_char(lexer); return lexer->curr = LexerToken_DollarSign;
		case ':': lexer_next_char(lexer); return lexer->curr = LexerToken_Colon;
		case '\n': lexer_next_char(lexer); return lexer->curr = LexerToken_Newline;
		case EOF: return lexer->curr = LexerToken_EndOfFile;
	}

	Assert(false, "unknown character '%c' received\n", lexer->current_char);
	return LexerToken_Unknown;
}

C8 lexer_next_char(Lexer* lexer) {
	if(lexer_is_at_end(lexer)) {
		if(lexer->current_char != EOF) lexer->index++;
		return lexer->current_char = EOF;
	}
	return lexer->current_char = (C8)lexer->source.ptr[lexer->index++];
}

B32 lexer_is_at_end(Lexer* lexer) { return lexer->index >= lexer->source.size; }

void lexer_consume_spaces(Lexer* lexer) {
	// consume spaces (excluding newlines)
	while(lexer_is_whitespace(lexer->current_char)) { lexer_next_char(lexer); }
}

B32 lexer_is_whitespace(C8 c) {
	return (c == '\t' || c == '\v' || c == '\f' || c == '\r' || c == ' ');
}

LexerToken lexer_next_tok_identifier(Lexer* lexer) {
	const U64 start = lexer->index - 1;

	while(isalnum(lexer->current_char) || lexer->current_char == '_' || lexer->current_char == '.') {
		lexer_next_char(lexer);
	}

	const U64 end = lexer->index - 1;
	lexer->curr_string = str_make(lexer->source.ptr + start, end - start);

	const auto LexerToken = lexer_str_to_tok(lexer->curr_string);

	if(LexerToken != LexerToken_Unknown) { return lexer->curr = LexerToken; }

	// numerical literal
	if(lexer->curr_string.size > 0 && isdigit(lexer->curr_string.ptr[0])) {
		return lexer_str_to_num_tok(lexer, lexer->curr_string);
	}

	return lexer->curr = LexerToken_Identifier;
}

LexerToken lexer_next_tok_comment(Lexer* lexer) {
	do { lexer_next_char(lexer); } while(!lexer_is_at_end(lexer) && lexer->current_char != '\n');

	// return the next LexerToken
	return lexer_next_tok(lexer);
}

LexerToken lexer_next_tok_string(Lexer* lexer) {
	Assert(false, "TODO: next_tok_string");
	return LexerToken_Unknown;
}

LexerToken lexer_next_tok_char(Lexer* lexer) {
	Assert(false, "TODO: next_tok_char");
	return LexerToken_Unknown;
}

LexerToken lexer_str_to_tok(Str str) {
	// numeric register (x1, x2,...)
	if(str.size > 1 && str.ptr[0] == 'x') {
		C8 buf[16] = {0};
		const U64 n = str.size < 15 ? str.size : 15;
		memcpy(buf, str.ptr, n);
		buf[n] = 0;

		C8* end;
		I64 reg_num = strtol(buf + 1, &end, 10);
		if(*end == '\0' && reg_num >= 0 && reg_num <= 31) {
			return (LexerToken)((U32)LexerToken_RegX0 + reg_num);
		}
	}

	typedef struct RegMapping {
		const C8* name;
		LexerToken tok;
	} RegMapping;

	// ABI names
	static const RegMapping abi_map[] = {
		{"zero", LexerToken_RegX0}, {"ra", LexerToken_RegX1},		{"sp", LexerToken_RegX2},
		{"gp", LexerToken_RegX3},		{"tp", LexerToken_RegX4},		{"t0", LexerToken_RegX5},
		{"t1", LexerToken_RegX6},		{"t2", LexerToken_RegX7},		{"s0", LexerToken_RegX8},
		{"fp", LexerToken_RegX8},		{"s1", LexerToken_RegX9},		{"a0", LexerToken_RegX10},
		{"a1", LexerToken_RegX11},	{"a2", LexerToken_RegX12},	{"a3", LexerToken_RegX13},
		{"a4", LexerToken_RegX14},	{"a5", LexerToken_RegX15},	{"a6", LexerToken_RegX16},
		{"a7", LexerToken_RegX17},	{"s2", LexerToken_RegX18},	{"s3", LexerToken_RegX19},
		{"s4", LexerToken_RegX20},	{"s5", LexerToken_RegX21},	{"s6", LexerToken_RegX22},
		{"s7", LexerToken_RegX23},	{"s8", LexerToken_RegX24},	{"s9", LexerToken_RegX25},
		{"s10", LexerToken_RegX26}, {"s11", LexerToken_RegX27}, {"t3", LexerToken_RegX28},
		{"t4", LexerToken_RegX29},	{"t5", LexerToken_RegX30},	{"t6", LexerToken_RegX31}};

	static const U64 abi_size = sizeof(abi_map) / sizeof(abi_map[0]);
	for(size_t i = 0; i < abi_size; ++i) {
		if(str_match_cstr(str, abi_map[i].name)) return abi_map[i].tok;
	}

	return LexerToken_Unknown;
}

LexerToken lexer_str_to_num_tok(Lexer* lexer, Str Str) {
	I32 base = 10;
	C8 buf[64];
	Assert(Str.size < sizeof(buf), "numeric literal too long ('%.*s')\n", (int)Str.size,
				 (const C8*)Str.ptr);
	memcpy(buf, Str.ptr, Str.size);
	if(Str.size >= sizeof(buf)) __builtin_unreachable();
	buf[Str.size] = 0;
	C8* data = buf;

	if(Str.size > 1 && buf[0] == '0') {
		switch(buf[1]) {
			case 'x':
				base = 16;
				data += 2;
				break;
			case '0' ... '7':
				base = 8;
				data += 1;
				break;
			case 'b':
				base = 2;
				data += 2;
				break;
			default: Assert(false, "unknown literal type\n");
		}
	}

	errno = 0;
	const U64 number = strtoull(data, 0, base);
	Assert(errno == 0, "strtoull failed for '%s'\n", buf);
	lexer->curr_imm = (I64)number;
	return lexer->curr = LexerToken_Number;
}