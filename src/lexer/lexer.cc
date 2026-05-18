#include "lexer/lexer.h"
#include "cpu/cpu.cuh"
#include <cstdlib>

namespace sup {
const c8* lex_token_to_str(token tok) {
	switch(tok) {
		case token::UNKNOWN: return "unknown";
		case token::IDENTIFIER: return "identifier";
		case token::NUMBER: return "number";
		case token::COMMA: return ",";
		case token::LBRACKET: return "[";
		case token::RBRACKET: return "]";
		case token::LBRACE: return "(";
		case token::RBRACE: return ")";
		case token::PLUS: return "+";
		case token::MINUS: return "-";
		case token::ASTERISK: return "*";
		case token::DOLLARSIGN: return "$";
		case token::COLON: return ":";
		case token::NEWLINE: return "newline";
		case token::END_OF_FILE: return "eof";
		default:
			if(lex_token_is_reg(tok)) {
				return reg_name(lex_token_to_reg_index(tok));
			}
			return "?";
	}
}

b32 lex_token_is_reg(token tok) {
	return tok >= token::REG_X0 && tok <= token::REG_X31;
}

u64 lex_token_to_reg_index(token tok) {
	ASSERT(lex_token_is_reg(tok), "token is not a register");
	return (u64)tok - (u64)token::REG_X0;
}

lexer lex_make(string source) {
	lexer lex;
	lex.index = 0;
	lex.source = source;
	lex.current_char = 0;
	lex.curr = token::UNKNOWN;
	lex.curr_imm = 0;
	return lex;
}

token lex_next_tok(lexer* lex) {
	lex->curr_string = {};

	// get rid of leading space-like characters
	lex_consume_spaces(lex);

	// special characters
	switch(lex->current_char) {
		case '_':
		case '.':
		case '0' ... '9':
		case 'a' ... 'z':
		case 'A' ... 'Z': return lex_next_tok_identifier(lex);

		case ';':
		case '#': return lex_next_tok_comment(lex);
		case '"': return lex_next_tok_string(lex);
		case '\'': return lex_next_tok_char(lex);

		case ',': lex_next_char(lex); return lex->curr = token::COMMA;
		case '[': lex_next_char(lex); return lex->curr = token::LBRACKET;
		case ']': lex_next_char(lex); return lex->curr = token::RBRACKET;
		case '(': lex_next_char(lex); return lex->curr = token::LBRACE;
		case ')': lex_next_char(lex); return lex->curr = token::RBRACE;
		case '+': lex_next_char(lex); return lex->curr = token::PLUS;
		case '-': lex_next_char(lex); return lex->curr = token::MINUS;
		case '*': lex_next_char(lex); return lex->curr = token::ASTERISK;
		case '$': lex_next_char(lex); return lex->curr = token::DOLLARSIGN;
		case ':': lex_next_char(lex); return lex->curr = token::COLON;
		case '\n': lex_next_char(lex); return lex->curr = token::NEWLINE;
		case EOF: return lex->curr = token::END_OF_FILE;
	}

	ASSERT(false, "unknown character '%c' received\n", lex->current_char);
	return token::UNKNOWN;
}

c8 lex_next_char(lexer* lex) {
	if(lex_is_at_end(lex)) { return lex->current_char = EOF; }
	return lex->current_char = (c8)lex->source[lex->index++];
}

b32 lex_is_at_end(lexer* lex) { return lex->index >= lex->source.size; }

void lex_consume_spaces(lexer* lex) {
	// consume spaces (excluding newlines)
	while(lex_is_whitespace(lex->current_char)) { lex_next_char(lex); }
}

b32 lex_is_whitespace(c8 c) {
	return (c == '\t' || c == '\v' || c == '\f' || c == '\r' || c == ' ');
}

token lex_next_tok_identifier(lexer* lex) {
	const u64 start = lex->index - 1;

	while(isalnum(lex->current_char) || lex->current_char == '_' ||
				lex->current_char == '.') {
		lex_next_char(lex);
	}

	const u64 end = lex->index - 1;
	lex->curr_string = string(lex->source.ptr + start, end - start);

	const auto token = lex_str_to_tok(lex->curr_string);

	if(token != token::UNKNOWN) { return lex->curr = token; }

	// numerical literal
	if(lex->curr_string.size > 0 && isdigit(lex->curr_string[0])) {
		return lex_str_to_num(lex, lex->curr_string);
	}

	return lex->curr = token::IDENTIFIER;
}

token lex_next_tok_comment(lexer* lex) {
	do {
		lex_next_char(lex);
	} while(!lex_is_at_end(lex) && lex->current_char != '\n');

	// return the next token
	return lex_next_tok(lex);
}

token lex_next_tok_string(lexer* lex) {
	ASSERT(false, "TODO: next_tok_string");
	return token::UNKNOWN;
}

token lex_next_tok_char(lexer* lex) {
	ASSERT(false, "TODO: next_tok_char");
	return token::UNKNOWN;
}

token lex_str_to_tok(string string) {
	// numeric register (x1, x2,...)
	if(string.size > 1 && string[0] == 'x') {
		c8 buf[16] = {0};
		const u64 n = string.size < 15 ? string.size : 15;
		memcpy(buf, string.ptr, n);
		buf[n] = 0;

		c8* end;
		i64 reg_num = strtol(buf + 1, &end, 10);
		if(*end == '\0' && reg_num >= 0 && reg_num <= 31) {
			return (token)((u32)token::REG_X0 + reg_num);
		}
	}

	struct reg_mapping {
		const c8* name;
		token tok;
	};

	// ABI names
	static const reg_mapping abi_map[] = {
		{"zero", token::REG_X0}, {"ra", token::REG_X1},		{"sp", token::REG_X2},
		{"gp", token::REG_X3},		{"tp", token::REG_X4},		{"t0", token::REG_X5},
		{"t1", token::REG_X6},		{"t2", token::REG_X7},		{"s0", token::REG_X8},
		{"fp", token::REG_X8},		{"s1", token::REG_X9},		{"a0", token::REG_X10},
		{"a1", token::REG_X11},	{"a2", token::REG_X12},	{"a3", token::REG_X13},
		{"a4", token::REG_X14},	{"a5", token::REG_X15},	{"a6", token::REG_X16},
		{"a7", token::REG_X17},	{"s2", token::REG_X18},	{"s3", token::REG_X19},
		{"s4", token::REG_X20},	{"s5", token::REG_X21},	{"s6", token::REG_X22},
		{"s7", token::REG_X23},	{"s8", token::REG_X24},	{"s9", token::REG_X25},
		{"s10", token::REG_X26}, {"s11", token::REG_X27}, {"t3", token::REG_X28},
		{"t4", token::REG_X29},	{"t5", token::REG_X30},	{"t6", token::REG_X31}};

	static const u64 abi_size = sizeof(abi_map) / sizeof(abi_map[0]);
	for(size_t i = 0; i < abi_size; ++i) {
		if(string == abi_map[i].name) return abi_map[i].tok;
	}

	return token::UNKNOWN;
}

token lex_str_to_num(lexer* lex, string string) {
	i32 base = 10;
	c8 buf[64];
	ASSERT(string.size < sizeof(buf), "numeric literal too long ('%.*s')\n",
				 (int)string.size, (const c8*)string.ptr);
	memcpy(buf, string.ptr, string.size);
	if(string.size >= sizeof(buf)) __builtin_unreachable();
	buf[string.size] = 0;
	c8* data = buf;

	if(string.size > 1 && buf[0] == '0') {
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
			default: ASSERT(false, "unknown literal type\n");
		}
	}

	errno = 0;
	const u64 number = strtoull(data, nullptr, base);
	ASSERT(errno == 0, "strtoull failed for '%s'\n", buf);
	lex->curr_imm = (i64)number;
	return lex->curr = token::NUMBER;
}
} // namespace sup