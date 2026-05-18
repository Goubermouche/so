#include "lexer/lexer.h"
#include "cpu/cpu.cuh"
#include <cstdlib>

namespace sup {
const c8* lex_token_to_str(lex_token tok) {
	switch(tok) {
		case TOK_UNKNOWN: return "unknown";
		case TOK_IDENTIFIER: return "identifier";
		case TOK_NUMBER: return "number";
		case TOK_COMMA: return ",";
		case TOK_LBRACKET: return "[";
		case TOK_RBRACKET: return "]";
		case TOK_LBRACE: return "(";
		case TOK_RBRACE: return ")";
		case TOK_PLUS: return "+";
		case TOK_MINUS: return "-";
		case TOK_ASTERISK: return "*";
		case TOK_DOLLARSIGN: return "$";
		case TOK_COLON: return ":";
		case TOK_NEWLINE: return "newline";
		case TOK_EOF: return "eof";
		default:
			if(tok >= TOK_REG_X0 && tok <= TOK_REG_X31) {
				return reg_name((u32)(tok - TOK_REG_X0));
			}
			return "?";
	}
}

b32 lex_token_is_reg(lex_token tok) {
	return tok >= TOK_REG_X0 && tok <= TOK_REG_X31;
}

u64 lex_token_to_reg_index(lex_token tok) {
	ASSERT(lex_token_is_reg(tok), "token is not a register");
	return tok - TOK_REG_X0;
}

lex_lexer lex_make(string source) {
	lex_lexer lex;
	lex.index = 0;
	lex.source = source;
	lex.current_char = 0;
	lex.curr = TOK_UNKNOWN;
	lex.curr_imm = 0;
	return lex;
}

lex_token lex_next_tok(lex_lexer* lex) {
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

		case ',': lex_next_char(lex); return lex->curr = TOK_COMMA;
		case '[': lex_next_char(lex); return lex->curr = TOK_LBRACKET;
		case ']': lex_next_char(lex); return lex->curr = TOK_RBRACKET;
		case '(': lex_next_char(lex); return lex->curr = TOK_LBRACE;
		case ')': lex_next_char(lex); return lex->curr = TOK_RBRACE;
		case '+': lex_next_char(lex); return lex->curr = TOK_PLUS;
		case '-': lex_next_char(lex); return lex->curr = TOK_MINUS;
		case '*': lex_next_char(lex); return lex->curr = TOK_ASTERISK;
		case '$': lex_next_char(lex); return lex->curr = TOK_DOLLARSIGN;
		case ':': lex_next_char(lex); return lex->curr = TOK_COLON;
		case '\n': lex_next_char(lex); return lex->curr = TOK_NEWLINE;
		case EOF: return lex->curr = TOK_EOF;
	}

	ASSERT(false, "unknown character '%c' received\n", lex->current_char);
	return TOK_UNKNOWN;
}

c8 lex_next_char(lex_lexer* lex) {
	if(lex_is_at_end(lex)) { return lex->current_char = EOF; }
	return lex->current_char = (c8)lex->source[lex->index++];
}

b32 lex_is_at_end(lex_lexer* lex) { return lex->index >= lex->source.size; }

void lex_consume_spaces(lex_lexer* lex) {
	// consume spaces (excluding newlines)
	while(lex_is_whitespace(lex->current_char)) { lex_next_char(lex); }
}

b32 lex_is_whitespace(c8 c) {
	return (c == '\t' || c == '\v' || c == '\f' || c == '\r' || c == ' ');
}

lex_token lex_next_tok_identifier(lex_lexer* lex) {
	const u64 start = lex->index - 1;

	while(isalnum(lex->current_char) || lex->current_char == '_' ||
				lex->current_char == '.') {
		lex_next_char(lex);
	}

	const u64 end = lex->index - 1;
	lex->curr_string = string(lex->source.ptr + start, end - start);

	const auto token = lex_str_to_tok(lex->curr_string);

	if(token != TOK_UNKNOWN) { return lex->curr = token; }

	// numerical literal
	if(lex->curr_string.size > 0 && isdigit(lex->curr_string[0])) {
		return lex_str_to_num(lex, lex->curr_string);
	}

	return lex->curr = TOK_IDENTIFIER;
}

lex_token lex_next_tok_comment(lex_lexer* lex) {
	do {
		lex_next_char(lex);
	} while(!lex_is_at_end(lex) && lex->current_char != '\n');

	// return the next token
	return lex_next_tok(lex);
}

lex_token lex_next_tok_string(lex_lexer* lex) {
	ASSERT(false, "TODO: next_tok_string");
	return TOK_UNKNOWN;
}

lex_token lex_next_tok_char(lex_lexer* lex) {
	ASSERT(false, "TODO: next_tok_char");
	return TOK_UNKNOWN;
}

lex_token lex_str_to_tok(string string) {
	// numeric register (x1, x2,...)
	if(string.size > 1 && string[0] == 'x') {
		c8 buf[16] = {0};
		const u64 n = string.size < 15 ? string.size : 15;
		memcpy(buf, string.ptr, n);
		buf[n] = 0;

		c8* end;
		i64 reg_num = strtol(buf + 1, &end, 10);
		if(*end == '\0' && reg_num >= 0 && reg_num <= 31) {
			return (lex_token)(TOK_REG_X0 + reg_num);
		}
	}

	struct reg_mapping {
		const c8* name;
		lex_token tok;
	};

	// ABI names
	static const reg_mapping abi_map[] = {
		{"zero", TOK_REG_X0}, {"ra", TOK_REG_X1},		{"sp", TOK_REG_X2},
		{"gp", TOK_REG_X3},		{"tp", TOK_REG_X4},		{"t0", TOK_REG_X5},
		{"t1", TOK_REG_X6},		{"t2", TOK_REG_X7},		{"s0", TOK_REG_X8},
		{"fp", TOK_REG_X8},		{"s1", TOK_REG_X9},		{"a0", TOK_REG_X10},
		{"a1", TOK_REG_X11},	{"a2", TOK_REG_X12},	{"a3", TOK_REG_X13},
		{"a4", TOK_REG_X14},	{"a5", TOK_REG_X15},	{"a6", TOK_REG_X16},
		{"a7", TOK_REG_X17},	{"s2", TOK_REG_X18},	{"s3", TOK_REG_X19},
		{"s4", TOK_REG_X20},	{"s5", TOK_REG_X21},	{"s6", TOK_REG_X22},
		{"s7", TOK_REG_X23},	{"s8", TOK_REG_X24},	{"s9", TOK_REG_X25},
		{"s10", TOK_REG_X26}, {"s11", TOK_REG_X27}, {"t3", TOK_REG_X28},
		{"t4", TOK_REG_X29},	{"t5", TOK_REG_X30},	{"t6", TOK_REG_X31}};

	static const u64 abi_size = sizeof(abi_map) / sizeof(abi_map[0]);
	for(size_t i = 0; i < abi_size; ++i) {
		if(string == abi_map[i].name) return abi_map[i].tok;
	}

	return TOK_UNKNOWN;
}

lex_token lex_str_to_num(lex_lexer* lex, string string) {
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
	return lex->curr = TOK_NUMBER;
}
} // namespace sup