#include "int/lexer.h"
#include "int/cpu.cuh"

const char* int_token_to_str(int_token tok) {
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
			if(tok >= TOK_REG_X0 && tok <= TOK_REG_X31) { return int_reg_name((u32)(tok - TOK_REG_X0)); }
			return "?";
	}
}

b32 int_token_is_reg(int_token tok) { return tok >= TOK_REG_X0 && tok <= TOK_REG_X31; }

u64 int_token_to_reg_index(int_token tok) {
	ASSERT(int_token_is_reg(tok), "token is not a register");
	return tok - TOK_REG_X0;
}

int_lexer int_lexer_make(const str& source) {
	int_lexer lex;
	lex.index = 0;
	lex.source = source;
	return lex;
}

int_token int_lexer_next_tok(int_lexer* lex) {
	lex->curr_string.clear();

	// get rid of leading space-like characters
	int_lexer_consume_spaces(lex);

	// special characters
	switch(lex->current_char) {
		case '_':
		case '.':
		case '0' ... '9':
		case 'a' ... 'z':
		case 'A' ... 'Z': return int_lexer_next_tok_identifier(lex);

		case ';':
		case '#': return int_lexer_next_tok_comment(lex);
		case '"': return int_lexer_next_tok_string(lex);
		case '\'': return int_lexer_next_tok_char(lex);

		case ',': int_lexer_next_char(lex); return lex->curr = TOK_COMMA;
		case '[': int_lexer_next_char(lex); return lex->curr = TOK_LBRACKET;
		case ']': int_lexer_next_char(lex); return lex->curr = TOK_RBRACKET;
		case '(': int_lexer_next_char(lex); return lex->curr = TOK_LBRACE;
		case ')': int_lexer_next_char(lex); return lex->curr = TOK_RBRACE;
		case '+': int_lexer_next_char(lex); return lex->curr = TOK_PLUS;
		case '-': int_lexer_next_char(lex); return lex->curr = TOK_MINUS;
		case '*': int_lexer_next_char(lex); return lex->curr = TOK_ASTERISK;
		case '$': int_lexer_next_char(lex); return lex->curr = TOK_DOLLARSIGN;
		case ':': int_lexer_next_char(lex); return lex->curr = TOK_COLON;
		case '\n': int_lexer_next_char(lex); return lex->curr = TOK_NEWLINE;
		case EOF: return lex->curr = TOK_EOF;
	}

	ASSERT(false, "unknown character '%c' received\n", lex->current_char);
	return TOK_UNKNOWN;
}

char int_lexer_next_char(int_lexer* lex) {
	if(int_lexer_is_at_end(lex)) { return lex->current_char = EOF; }
	return lex->current_char = lex->source[lex->index++];
}

b32 int_lexer_is_at_end(int_lexer* lex) { return lex->index >= lex->source.size(); }

void int_lexer_consume_spaces(int_lexer* lex) {
	// consume spaces (excluding newlines)
	while(int_lexer_is_whitespace(lex->current_char)) { int_lexer_next_char(lex); }
}

b32 int_lexer_is_whitespace(char c) {
	return (c == '\t' || c == '\v' || c == '\f' || c == '\r' || c == ' ');
}

int_token int_lexer_next_tok_identifier(int_lexer* lex) {
	// '.' is allowed inside mnemonics like sext.b / zext.h. dashes don't appear
	while(isalnum(lex->current_char) || lex->current_char == '_' || lex->current_char == '.') {
		lex->curr_string += lex->current_char;
		int_lexer_next_char(lex);
	}

	const auto token = int_lexer_string_to_tok(lex->curr_string);

	if(token != TOK_UNKNOWN) { return lex->curr = token; }

	// numerical literal
	if(isdigit(lex->curr_string[0])) { return int_lexer_string_to_num(lex, lex->curr_string); }

	return lex->curr = TOK_IDENTIFIER;
}

int_token int_lexer_next_tok_comment(int_lexer* lex) {
	// skip over comments (both ';' and '#' style supported - '#' is the
	// gas/clang convention for RISC-V)
	do { int_lexer_next_char(lex); } while(!int_lexer_is_at_end(lex) && lex->current_char != '\n');

	// return the next token
	return int_lexer_next_tok(lex);
}

int_token int_lexer_next_tok_string(int_lexer* lex) {
	ASSERT(false, "TODO: next_tok_string");
	return TOK_UNKNOWN;
}

int_token int_lexer_next_tok_char(int_lexer* lex) {
	ASSERT(false, "TODO: next_tok_char");
	return TOK_UNKNOWN;
}

int_token int_lexer_string_to_tok(const str& string) {
	static const map<str, int_token> operand_map = {
		// numeric
		{"x0", TOK_REG_X0},
		{"x1", TOK_REG_X1},
		{"x2", TOK_REG_X2},
		{"x3", TOK_REG_X3},
		{"x4", TOK_REG_X4},
		{"x5", TOK_REG_X5},
		{"x6", TOK_REG_X6},
		{"x7", TOK_REG_X7},
		{"x8", TOK_REG_X8},
		{"x9", TOK_REG_X9},
		{"x10", TOK_REG_X10},
		{"x11", TOK_REG_X11},
		{"x12", TOK_REG_X12},
		{"x13", TOK_REG_X13},
		{"x14", TOK_REG_X14},
		{"x15", TOK_REG_X15},
		{"x16", TOK_REG_X16},
		{"x17", TOK_REG_X17},
		{"x18", TOK_REG_X18},
		{"x19", TOK_REG_X19},
		{"x20", TOK_REG_X20},
		{"x21", TOK_REG_X21},
		{"x22", TOK_REG_X22},
		{"x23", TOK_REG_X23},
		{"x24", TOK_REG_X24},
		{"x25", TOK_REG_X25},
		{"x26", TOK_REG_X26},
		{"x27", TOK_REG_X27},
		{"x28", TOK_REG_X28},
		{"x29", TOK_REG_X29},
		{"x30", TOK_REG_X30},
		{"x31", TOK_REG_X31},
		// ABI names
		{"zero", TOK_REG_X0},
		{"ra", TOK_REG_X1},
		{"sp", TOK_REG_X2},
		{"gp", TOK_REG_X3},
		{"tp", TOK_REG_X4},
		{"t0", TOK_REG_X5},
		{"t1", TOK_REG_X6},
		{"t2", TOK_REG_X7},
		{"s0", TOK_REG_X8},
		{"fp", TOK_REG_X8},
		{"s1", TOK_REG_X9},
		{"a0", TOK_REG_X10},
		{"a1", TOK_REG_X11},
		{"a2", TOK_REG_X12},
		{"a3", TOK_REG_X13},
		{"a4", TOK_REG_X14},
		{"a5", TOK_REG_X15},
		{"a6", TOK_REG_X16},
		{"a7", TOK_REG_X17},
		{"s2", TOK_REG_X18},
		{"s3", TOK_REG_X19},
		{"s4", TOK_REG_X20},
		{"s5", TOK_REG_X21},
		{"s6", TOK_REG_X22},
		{"s7", TOK_REG_X23},
		{"s8", TOK_REG_X24},
		{"s9", TOK_REG_X25},
		{"s10", TOK_REG_X26},
		{"s11", TOK_REG_X27},
		{"t3", TOK_REG_X28},
		{"t4", TOK_REG_X29},
		{"t5", TOK_REG_X30},
		{"t6", TOK_REG_X31},
	};

	const auto it = operand_map.find(string);

	if(it == operand_map.end()) { return TOK_UNKNOWN; }

	return it->second;
}

int_token int_lexer_string_to_num(int_lexer* lex, const str& string) {
	i32 base = 10;
	char* data = lex->curr_string.data();

	if(lex->curr_string[0] == '0' && lex->curr_string.size() > 1) {
		switch(lex->curr_string[1]) {
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
	ASSERT(errno == 0, "strtoull failed for '%s'\n", lex->curr_string.c_str());
	(void)string;
	lex->curr_imm = (i64)number;
	return lex->curr = TOK_NUMBER;
}
