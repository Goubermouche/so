#include "tokenizer.h"

namespace so {
	auto token_to_str(token tok) -> const char* {
		switch(tok) {
			case TOK_UNKNOWN:    return "unknown";
			case TOK_IDENTIFIER: return "identifier";
			case TOK_NUMBER:     return "number";
			case TOK_REG_EAX:    return "eax";
			case TOK_REG_EBX:    return "ebx";
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

	auto token_is_reg(token tok) -> bool {
		switch(tok) {
			case TOK_REG_EAX:
			case TOK_REG_EBX:
			case TOK_REG_ECX:
			case TOK_REG_EDX:
			case TOK_REG_ESI:
			case TOK_REG_EDI: return true;
			default: return false;
		}
	}

	auto token_to_reg_index(token tok) -> u64 {
		ASSERT(token_is_reg(tok), "token is not a register");
		return tok - TOK_REG_EAX;
	}

	tokenizer::tokenizer(const str& source) : m_source(source) {}

	auto tokenizer::next_tok() -> token {
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

	auto tokenizer::next_tok_identifier() -> token {
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

	auto tokenizer::next_tok_comment() -> token {
		// skip over comments
		do {
			next_char();
		} while(!is_at_end() && m_current_char != '\n');

		// return the next token
		return next_tok();
	}

	auto tokenizer::next_tok_string() -> token {
		ASSERT(false, "TODO: next_tok_string");
		return TOK_UNKNOWN;
	}

	auto tokenizer::next_tok_char() -> token {
		ASSERT(false, "TODO: next_tok_char");
		return TOK_UNKNOWN;
	}

	auto tokenizer::next_char() -> char {
		if(is_at_end()) {
			return m_current_char = EOF;
		}

		return m_current_char = m_source[m_index++];
	}

	auto tokenizer::is_at_end() -> bool {
		return m_index >= m_source.size();
	}

	void tokenizer::consume_spaces() {
		// consume spaces (excluding newlines)
		while(is_whitespace(m_current_char)) {
			next_char();
		}
	}

	auto tokenizer::is_whitespace(char c) -> bool {
		return (c == '\t' || c == '\v' || c == '\f' || c == '\r' || c == ' ');
	}

	auto tokenizer::string_to_token(const str& string) -> token {
		static const map<str, token> operand_map = {
			{ "eax", TOK_REG_EAX },
			{ "ebx", TOK_REG_EBX },
			{ "ecx", TOK_REG_ECX },
			{ "edx", TOK_REG_EDX },
			{ "esi", TOK_REG_ESI },
			{ "edi", TOK_REG_EDI },
		};

		const auto it = operand_map.find(string);

		if(it == operand_map.end()) {
			return TOK_UNKNOWN;
		}

		return it->second;
	}

	auto tokenizer::string_to_number(const str& string) -> token {
		i32 base = 10;
		char* data = curr_string.data();

		if(curr_string[0] == '0' && curr_string.size() > 1) {
			switch(curr_string[1]) {
				case 'x':         base = 16; data += 2; break; // hex
				case '0' ... '7': base = 8;  data += 1; break; // oct
				case 'b':         base = 2;  data += 2; break; // bin
				default: ASSERT(false, "unknown literal type\n");
			}
		}

		const u64 number = strtoull(data, nullptr, base);
		ASSERT(errno == 0, "strtoull failed for '{}'\n", curr_string);

		curr_imm = number;

		return curr = TOK_NUMBER;
	}
} // namespace so

