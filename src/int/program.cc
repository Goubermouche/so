#include "int/program.h"

const char* token_to_str(token tok) {
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
			if(tok >= TOK_REG_X0 && tok <= TOK_REG_X31) { return reg_name((u32)(tok - TOK_REG_X0)); }

			return "?";
	}
}

b32 token_is_reg(token tok) { return tok >= TOK_REG_X0 && tok <= TOK_REG_X31; }

u64 token_to_reg_index(token tok) {
	ASSERT(token_is_reg(tok), "token is not a register");
	return tok - TOK_REG_X0;
}

tokenizer::tokenizer(const str& source) : m_source(source) {}

token tokenizer::next_tok() {
	curr_string.clear();

	// get rid of leading space-like characters
	consume_spaces();

	// special characters
	switch(m_current_char) {
		case '_':
		case '.':
		case '0' ... '9':
		case 'a' ... 'z':
		case 'A' ... 'Z': return next_tok_identifier();

		case ';':
		case '#': return next_tok_comment();
		case '"': return next_tok_string();
		case '\'': return next_tok_char();

		case ',': next_char(); return curr = TOK_COMMA;
		case '[': next_char(); return curr = TOK_LBRACKET;
		case ']': next_char(); return curr = TOK_RBRACKET;
		case '(': next_char(); return curr = TOK_LBRACE;
		case ')': next_char(); return curr = TOK_RBRACE;
		case '+': next_char(); return curr = TOK_PLUS;
		case '-': next_char(); return curr = TOK_MINUS;
		case '*': next_char(); return curr = TOK_ASTERISK;
		case '$': next_char(); return curr = TOK_DOLLARSIGN;
		case ':': next_char(); return curr = TOK_COLON;
		case '\n': next_char(); return curr = TOK_NEWLINE;
		case EOF: return curr = TOK_EOF;
	}

	ASSERT(false, "unknown character '%c' received\n", m_current_char);
	return TOK_UNKNOWN;
}

token tokenizer::next_tok_identifier() {
	// '.' is allowed inside mnemonics like sext.b / zext.h. dashes don't appear.
	while(isalnum(m_current_char) || m_current_char == '_' || m_current_char == '.') {
		curr_string += m_current_char;
		next_char();
	}

	const auto token = string_to_token(curr_string);

	if(token != TOK_UNKNOWN) { return curr = token; }

	// numerical literal
	if(isdigit(curr_string[0])) { return string_to_number(curr_string); }

	return curr = TOK_IDENTIFIER;
}

token tokenizer::next_tok_comment() {
	// skip over comments (both ';' and '#' style supported - '#' is the
	// gas/clang convention for RISC-V)
	do { next_char(); } while(!is_at_end() && m_current_char != '\n');

	// return the next token
	return next_tok();
}

token tokenizer::next_tok_string() {
	ASSERT(false, "TODO: next_tok_string");
	return TOK_UNKNOWN;
}

token tokenizer::next_tok_char() {
	ASSERT(false, "TODO: next_tok_char");
	return TOK_UNKNOWN;
}

char tokenizer::next_char() {
	if(is_at_end()) { return m_current_char = EOF; }

	return m_current_char = m_source[m_index++];
}

b32 tokenizer::is_at_end() { return m_index >= m_source.size(); }

void tokenizer::consume_spaces() {
	// consume spaces (excluding newlines)
	while(is_whitespace(m_current_char)) { next_char(); }
}

b32 tokenizer::is_whitespace(char c) {
	return (c == '\t' || c == '\v' || c == '\f' || c == '\r' || c == ' ');
}

token tokenizer::string_to_token(const str& string) {
	static const map<str, token> operand_map = {
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

token tokenizer::string_to_number(const str& string) {
	i32 base = 10;
	char* data = curr_string.data();

	if(curr_string[0] == '0' && curr_string.size() > 1) {
		switch(curr_string[1]) {
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
	ASSERT(errno == 0, "strtoull failed for '%s'\n", curr_string.c_str());
	(void)string;
	curr_imm = (i64)number;
	return curr = TOK_NUMBER;
}

opcode find_inst_op(const str& name, const inst_spec::operand* operands, u8 operand_count) {
	for(u32 i = 0; i < (u32)OP_COUNT; ++i) {
		const inst_spec& spec = INST_DB_HOST.row[i];

		if(name != spec.name) { continue; }

		if(spec.get_operand_count() != operand_count) { continue; }

		b32 ok = true;

		for(u8 k = 0; k < operand_count; ++k) {
			if(spec.operands[k] != operands[k]) {
				ok = false;
				break;
			}
		}

		if(ok) { return (opcode)i; }
	}

	return OP_COUNT; // sentinel: "no match"
}

program program::parse(const str& source) {
	arr<inst> result;
	tokenizer tok(source);
	tok.next_char();
	tok.next_tok();

	while(tok.curr != TOK_EOF) {
		// skip leading blank lines between instructions
		while(tok.curr == TOK_NEWLINE) tok.next_tok();
		if(tok.curr == TOK_EOF) break;

		if(tok.curr == TOK_IDENTIFIER) {
			str saved = tok.curr_string;
			tok.next_tok();
			if(tok.curr == TOK_COLON) {
				tok.next_tok();
				if(tok.curr == TOK_NEWLINE) tok.next_tok();
				continue;
			}
			// not a label after all - rewind by re-parsing as a mnemonic
			inst curr_inst = {};
			inst_spec::operand operand_types[4] = {};
			u8 operand_count = 0;

			while(tok.curr != TOK_NEWLINE && tok.curr != TOK_EOF && operand_count < 4) {
				if(token_is_reg(tok.curr)) {
					curr_inst.operands[operand_count].reg =
						static_cast<reg_index>(token_to_reg_index(tok.curr));
					operand_types[operand_count] = inst_spec::REG;
				} else if(tok.curr == TOK_NUMBER) {
					curr_inst.operands[operand_count].i = (u64)tok.curr_imm;
					operand_types[operand_count] = inst_spec::IMM;
				} else if(tok.curr == TOK_MINUS) {
					tok.next_tok();
					ASSERT(tok.curr == TOK_NUMBER, "expected number after '-'");
					curr_inst.operands[operand_count].i = (u64)(-tok.curr_imm);
					operand_types[operand_count] = inst_spec::IMM;
				} else {
					ASSERT(false, "unrecognized operand type received ('%s')", token_to_str(tok.curr));
				}

				operand_count++;

				if(tok.next_tok() != TOK_COMMA) break;
				tok.next_tok();
			}

			// pseudo-op rewriting
			//   sext.w rd, rs1   ->   addiw rd, rs1, 0
			if(saved == "sext.w" && operand_count == 2 && operand_types[0] == inst_spec::REG &&
				 operand_types[1] == inst_spec::REG) {
				saved = "addiw";
				curr_inst.operands[2].i = 0;
				operand_types[2] = inst_spec::IMM;
				operand_count = 3;
			}

			curr_inst.op = find_inst_op(saved, operand_types, operand_count);
			ASSERT(curr_inst.op != OP_COUNT, "no opcode matches mnemonic '%s' with %d operand(s)\n",
						 saved.c_str(), (int)operand_count);
			result.push_back(curr_inst);

			if(tok.curr == TOK_NEWLINE) { tok.next_tok(); }
			continue;
		}

		ASSERT(false, "expected mnemonic, got '%s'", token_to_str(tok.curr));
	}

	return {result};
}

program program::dce(const inst* prog, u32 prog_len, u64 live_mask) {
	// x0 is never live in the user-facing sense (writes are dropped)
	u64 live = live_mask & ~1ULL;
	u64 live_bits_by_slot = 0;
	u32 count = 0;

	for(i32 i = (i32)prog_len - 1; i >= 0; --i) {
		const inst_spec* spec = find_spec(prog[i].op);

		if(spec->dst_slot < 0) { continue; }

		const u32 dst = (u32)prog[i].operands[spec->dst_slot].reg;

		// writes to x0 are nops
		if(dst == 0) { continue; }

		const u64 dst_bit = 1ULL << dst;

		if(live & dst_bit) {
			++count;
			live_bits_by_slot |= (1ULL << i);

			// no rmw semantics
			live &= ~dst_bit;

			if(spec->src_slot >= 0) {
				const u32 src = (u32)prog[i].operands[spec->src_slot].reg;
				live |= 1ULL << src;
			}

			if(spec->src2_slot >= 0) {
				const u32 src2 = (u32)prog[i].operands[spec->src2_slot].reg;
				live |= 1ULL << src2;
			}
		}
	}

	program out;

	for(u32 i = 0; i < prog_len; ++i) {
		if(live_bits_by_slot & (1ULL << i)) { out.instructions.push_back(prog[i]); }
	}

	return out;
}

str program::to_string() const {
	str result;

	for(const inst& i : instructions) {
		const inst_spec* spec = find_spec(i.op);
		result += "    " + pad_to_length(spec->name, ' ', 8);

		for(u8 j = 0; j < spec->get_operand_count(); ++j) {
			result += operand_to_string(i.operands[j], spec->operands[j]);

			if(j + 1 < spec->get_operand_count()) { result += ", "; }
		}

		result += '\n';
	}

	return result;
}

u64 program::live_outs() const {
	u64 touched = 0;
	u64 live_out = 0;

	for(u64 idx = instructions.size(); idx-- > 0;) {
		const inst& in = instructions[idx];
		const inst_spec* spec = find_spec(in.op);

		// write side first
		if(spec->dst_slot >= 0) {
			const u32 r = (u32)in.operands[spec->dst_slot].reg;

			// x0 writes don't define anything
			if(r != 0) {
				const u64 bit = 1ULL << r;

				if(!(touched & bit)) {
					live_out |= bit;
					touched |= bit;
				}
			}
		}

		// read side
		if(spec->src_slot >= 0) {
			const u32 r = (u32)in.operands[spec->src_slot].reg;
			touched |= 1ULL << r;
		}

		if(spec->src2_slot >= 0) {
			const u32 r = (u32)in.operands[spec->src2_slot].reg;
			touched |= 1ULL << r;
		}
	}

	return live_out;
}

str program::operand_to_string(inst::operand op, inst_spec::operand ty) const {
	switch(ty) {
		case inst_spec::REG: return reg_name((u32)op.reg);
		case inst_spec::IMM: return std::to_string((i64)op.i);
		default: return "?";
	}
}
