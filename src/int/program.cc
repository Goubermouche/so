#include "int/program.h"

namespace so {
	const char* token_to_str(token tok) {
		switch(tok) {
			case TOK_UNKNOWN:    return "unknown";
			case TOK_IDENTIFIER: return "identifier";
			case TOK_NUMBER:     return "number";
			case TOK_REG_RAX:    return "rax";
			case TOK_REG_RBX:    return "rbx";
			case TOK_REG_RCX:    return "rcx";
			case TOK_REG_RDX:    return "rdx";
			case TOK_REG_RSI:    return "rsi";
			case TOK_REG_RDI:    return "rdi";
			case TOK_REG_RBP:    return "rbp";
			case TOK_REG_RSP:    return "rsp";
			case TOK_REG_R8:     return "r8";
			case TOK_REG_R9:     return "r9";
			case TOK_REG_R10:    return "r10";
			case TOK_REG_R11:    return "r11";
			case TOK_REG_R12:    return "r12";
			case TOK_REG_R13:    return "r13";
			case TOK_REG_R14:    return "r14";
			case TOK_REG_R15:    return "r15";
			case TOK_COMMA:      return ",";
			case TOK_LBRACKET:   return "[";
			case TOK_RBRACKET:   return "]";
			case TOK_LBRACE:     return "(";
			case TOK_RBRACE:     return ")";
			case TOK_PLUS:       return "+";
			case TOK_MINUS:      return "-";
			case TOK_ASTERISK:   return "*";
			case TOK_DOLLARSIGN: return "$";
			case TOK_COLON:      return ":";
			case TOK_NEWLINE:    return "newline";
			case TOK_EOF:        return "eof";
			default:             return "?";
		}
	}

	b32 token_is_reg(token tok) {
		return tok >= TOK_REG_RAX && tok <= TOK_REG_R15;
	}

	u64 token_to_reg_index(token tok) {
		ASSERT(token_is_reg(tok), "token is not a register");
		return tok - TOK_REG_RAX;
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

			case ';':  return next_tok_comment();
			case '"':  return next_tok_string();
			case '\'': return next_tok_char();

			case ',':  next_char(); return curr = TOK_COMMA;
			case '[':  next_char(); return curr = TOK_LBRACKET;
			case ']':  next_char(); return curr = TOK_RBRACKET;
			case '{':  next_char(); return curr = TOK_LBRACE;
			case '}':  next_char(); return curr = TOK_RBRACE;
			case '+':  next_char(); return curr = TOK_PLUS;
			case '-':  next_char(); return curr = TOK_MINUS;
			case '*':  next_char(); return curr = TOK_ASTERISK;
			case '$':  next_char(); return curr = TOK_DOLLARSIGN;
			case ':':  next_char(); return curr = TOK_COLON;
			case '\n': next_char(); return curr = TOK_NEWLINE;
			case EOF:               return curr = TOK_EOF;
		}

		ASSERT(false, "unknown character '{}' received\n", m_current_char);
		return TOK_UNKNOWN;
	}

	token tokenizer::next_tok_identifier() {
		while(isalnum(m_current_char) || m_current_char == '_' || m_current_char == '.') {
			curr_string += m_current_char;
			next_char();
		}

		const auto token = string_to_token(curr_string);

		if(token != TOK_UNKNOWN) {
			return curr = token;
		}

		// numerical literal
		if(isdigit(curr_string[0])) {
			return string_to_number(curr_string);
		}

		return curr = TOK_IDENTIFIER;
	}

	token tokenizer::next_tok_comment() {
		// skip over comments
		do {
			next_char();
		} while(!is_at_end() && m_current_char != '\n');

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
		if(is_at_end()) {
			return m_current_char = EOF;
		}

		return m_current_char = m_source[m_index++];
	}

	b32 tokenizer::is_at_end() {
		return m_index >= m_source.size();
	}

	void tokenizer::consume_spaces() {
		// consume spaces (excluding newlines)
		while(is_whitespace(m_current_char)) {
			next_char();
		}
	}

	b32 tokenizer::is_whitespace(char c) {
		return (c == '\t' || c == '\v' || c == '\f' || c == '\r' || c == ' ');
	}

	token tokenizer::string_to_token(const str& string) {
		static const map<str, token> operand_map = {
			{ "rax", TOK_REG_RAX }, { "eax",  TOK_REG_RAX },
			{ "rbx", TOK_REG_RBX }, { "ebx",  TOK_REG_RBX },
			{ "rcx", TOK_REG_RCX }, { "ecx",  TOK_REG_RCX },
			{ "rdx", TOK_REG_RDX }, { "edx",  TOK_REG_RDX },
			{ "rsi", TOK_REG_RSI }, { "esi",  TOK_REG_RSI },
			{ "rdi", TOK_REG_RDI }, { "edi",  TOK_REG_RDI },
			{ "rbp", TOK_REG_RBP }, { "ebp",  TOK_REG_RBP },
			{ "rsp", TOK_REG_RSP }, { "esp",  TOK_REG_RSP },
			{ "r8",  TOK_REG_R8  }, { "r8d",  TOK_REG_R8  },
			{ "r9",  TOK_REG_R9  }, { "r9d",  TOK_REG_R9  },
			{ "r10", TOK_REG_R10 }, { "r10d", TOK_REG_R10 },
			{ "r11", TOK_REG_R11 }, { "r11d", TOK_REG_R11 },
			{ "r12", TOK_REG_R12 }, { "r12d", TOK_REG_R12 },
			{ "r13", TOK_REG_R13 }, { "r13d", TOK_REG_R13 },
			{ "r14", TOK_REG_R14 }, { "r14d", TOK_REG_R14 },
			{ "r15", TOK_REG_R15 }, { "r15d", TOK_REG_R15 },
		};

		const auto it = operand_map.find(string);

		if(it == operand_map.end()) {
			return TOK_UNKNOWN;
		}

		return it->second;
	}

	token tokenizer::string_to_number(const str& string) {
		i32 base = 10;
		char* data = curr_string.data();

		if(curr_string[0] == '0' && curr_string.size() > 1) {
			switch(curr_string[1]) {
				case 'x':         base = 16; data += 2; break;
				case '0' ... '7': base = 8;  data += 1; break;
				case 'b':         base = 2;  data += 2; break;
				default: ASSERT(false, "unknown literal type\n");
			}
		}

		errno = 0;
		const u64 number = strtoull(data, nullptr, base);
		ASSERT(errno == 0, "strtoull failed for '{}'\n", curr_string);
		(void)string;
		curr_imm = number;
		return curr = TOK_NUMBER;
	}

	opcode find_inst_op(const str& name, const inst_spec::operand* operands, u8 operand_count) {
		for(u32 i = 0; i < (u32)OP_COUNT; ++i) {
			const inst_spec& spec = INST_DB_HOST.row[i];

			if(name != spec.name) {
				continue;
			}

			if(spec.get_operand_count() != operand_count) {
				continue;
			}

			b32 ok = true;

			for(u8 k = 0; k < operand_count; ++k) {
				if(spec.operands[k] != operands[k]) {
					ok = false;
					break;
				}
			}

			if(ok) {
				return (opcode)i;
			}
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

			// mnemonic
			inst curr_inst = {};
			inst_spec::operand operand_types[4] = {};
			u8 operand_count = 0;
			const str curr_name = tok.curr_string;
			tok.next_tok();

			// TODO: lea takes memory-operand syntax; handle it separately for now
			if(curr_name == "lea") {
				ASSERT(token_is_reg(tok.curr), "lea: expected destination register, got '{}'", token_to_str(tok.curr));
				curr_inst.operands[0].reg = static_cast<reg_index>(token_to_reg_index(tok.curr));
				tok.next_tok();
				ASSERT(tok.curr == TOK_COMMA, "lea: expected ',' after destination");
				tok.next_tok();
				ASSERT(tok.curr == TOK_LBRACKET, "lea: expected '[' to start memory operand");
				tok.next_tok();
				ASSERT(token_is_reg(tok.curr), "lea: expected base register inside brackets");
				curr_inst.operands[1].reg = static_cast<reg_index>(token_to_reg_index(tok.curr));
				tok.next_tok();
				ASSERT(tok.curr == TOK_PLUS, "lea: expected '+' between base and index");
				tok.next_tok();
				ASSERT(token_is_reg(tok.curr), "lea: expected index register after '+'");
				curr_inst.operands[2].reg = static_cast<reg_index>(token_to_reg_index(tok.curr));
				tok.next_tok();

				// optional scale:
				u32 scale = 1;

				if(tok.curr == TOK_ASTERISK) {
					tok.next_tok();
					ASSERT(tok.curr == TOK_NUMBER, "lea: expected scale after '*'");
					scale = (u32)tok.curr_imm;
					ASSERT(scale == 1 || scale == 2 || scale == 4 || scale == 8, "lea: scale must be 1, 2, 4, or 8 (got {})", (int)scale);
					tok.next_tok();
				}

				ASSERT(tok.curr == TOK_RBRACKET, "lea: expected ']' to close memory operand");
				tok.next_tok();

				switch(scale) {
					case 1: curr_inst.op = OP_LEA_R64_R64_R64_S1; break;
					case 2: curr_inst.op = OP_LEA_R64_R64_R64_S2; break;
					case 4: curr_inst.op = OP_LEA_R64_R64_R64_S4; break;
					case 8: curr_inst.op = OP_LEA_R64_R64_R64_S8; break;
				}

				result.push_back(curr_inst);

				if(tok.curr == TOK_NEWLINE) {
					tok.next_tok();
				}

				continue;
			}

			while(tok.curr != TOK_NEWLINE && tok.curr != TOK_EOF && operand_count < 2) {
				if(token_is_reg(tok.curr)) {
					curr_inst.operands[operand_count].reg = static_cast<reg_index>(token_to_reg_index(tok.curr));
					operand_types[operand_count] = inst_spec::R64;
				}
				else if(tok.curr == TOK_NUMBER) {
					curr_inst.operands[operand_count].i = tok.curr_imm;
					operand_types[operand_count] = inst_spec::I64;
				}
				else {
					ASSERT(false, "unrecognized operand type received ('{}')", token_to_str(tok.curr));
				}

				operand_count++;

				if(tok.next_tok() != TOK_COMMA) break;
				tok.next_tok(); // consume the comma
			}

			curr_inst.op = find_inst_op(curr_name, operand_types, operand_count);
			ASSERT(curr_inst.op != OP_COUNT, "no opcode matches mnemonic '{}' with {} operand(s)\n", curr_name, (int)operand_count);
			result.push_back(curr_inst);

			// tolerate either newline or EOF as an instruction terminator
			if(tok.curr == TOK_NEWLINE) {
				tok.next_tok();
			}
		}

		return { result };
	}

	program program::dce(const inst* prog, u32 prog_len, u64 live_mask) {
		u64 live = live_mask;
		u32 live_bits_by_slot = 0;
		u32 count = 0;

		for(i32 i = (i32)prog_len - 1; i >= 0; --i) {
			const inst_spec& spec = find_spec(prog[i].op);

			if(spec.dst_slot < 0) {
				continue;
			}

			const u32 dst = (u32)prog[i].operands[spec.dst_slot].reg;
			const u64 dst_bit = 1ULL << dst;

			if(live & dst_bit) {
				++count;
				live_bits_by_slot |= (1u << i);

				if(!spec.rmw) {
					live &= ~dst_bit;
				}

				if(spec.src_slot >= 0) {
					const u32 src = (u32)prog[i].operands[spec.src_slot].reg;
					live |= 1ULL << src;
				}

				if(spec.src2_slot >= 0) {
					const u32 src2 = (u32)prog[i].operands[spec.src2_slot].reg;
					live |= 1ULL << src2;
				}
			}
		}

		program out;

		for(u32 i = 0; i < prog_len; ++i) {
			if(live_bits_by_slot & (1u << i)) {
				out.instructions.push_back(prog[i]);
			}
		}

		return out;
	}

	static u32 lea_scale_for(opcode op) {
		switch(op) {
			case OP_LEA_R64_R64_R64_S1: return 1;
			case OP_LEA_R64_R64_R64_S2: return 2;
			case OP_LEA_R64_R64_R64_S4: return 4;
			case OP_LEA_R64_R64_R64_S8: return 8;
			default: return 0;
		}
	}

	str program::to_string() const {
		str result;

		for(const inst& i : instructions) {
			const inst_spec& spec = find_spec(i.op);
			result += "  " + pad_to_length(spec.name, ' ', 8);

			if(const u32 scale = lea_scale_for(i.op)) {
				result += reg_name((u32)i.operands[0].reg);
				result += ", [";
				result += reg_name((u32)i.operands[1].reg);
				result += " + ";
				result += reg_name((u32)i.operands[2].reg);

				if(scale != 1) {
					result += "*";
					result += std::to_string(scale);
				}

				result += "]\n";
				continue;
			}

			for(u8 j = 0; j < spec.get_operand_count(); ++j) {
				result += operand_to_string(i.operands[j], spec.operands[j]);

				if(j + 1 < spec.get_operand_count()) {
					result += ", ";
				}
			}

			result += '\n';
		}

		return result;
	}

	u64 program::live_outs() const {
		u64 touched  = 0;
		u64 live_out = 0;

		for(u64 idx = instructions.size(); idx-- > 0;) {
			const inst& in = instructions[idx];
			const inst_spec& spec = find_spec(in.op);

			// write side first
			if(spec.dst_slot >= 0) {
				const u32 r = (u32)in.operands[spec.dst_slot].reg;
				const u64 bit = 1ULL << r;

				if(!(touched & bit)) {
					live_out |= bit;
					touched  |= bit;
				}
			}

			// read side
			if(spec.src_slot >= 0) {
				const u32 r = (u32)in.operands[spec.src_slot].reg;
				touched |= 1ULL << r;
			}

			if(spec.src2_slot >= 0) {
				const u32 r = (u32)in.operands[spec.src2_slot].reg;
				touched |= 1ULL << r;
			}

			if(spec.rmw && spec.dst_slot >= 0) {
				const u32 r = (u32)in.operands[spec.dst_slot].reg;
				touched |= 1ULL << r;
			}
		}

		return live_out;
	}

	str program::operand_to_string(inst::operand op, inst_spec::operand ty) const {
		switch(ty) {
			case inst_spec::R64: return reg_name((u32)op.reg);
			case inst_spec::I64: return std::to_string((i64)op.i);
			default:             return "?";
		}
	}
} // namespace so

