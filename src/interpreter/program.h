#ifndef PROGRAM_H
#define PROGRAM_H

#include "interpreter/instruction.h"

namespace so {
	enum token {
		TOK_UNKNOWN = 0,

		TOK_IDENTIFIER,
		TOK_NUMBER,

		// regs
		TOK_REG_EAX,
		TOK_REG_EBX,
		TOK_REG_ECX,
		TOK_REG_EDX,
		TOK_REG_ESI,
		TOK_REG_EDI,

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
	};

	auto token_to_str(token tok) -> const char*;
	auto token_is_reg(token tok) -> bool;
	auto token_to_reg_index(token tok) -> u64;

	struct tokenizer {
		tokenizer(const str& source);

		auto next_tok() -> token;
		auto next_tok_identifier() -> token;
		auto next_tok_comment() -> token;
		auto next_tok_string() -> token;
		auto next_tok_char() -> token;

		auto next_char() -> char;
		auto is_at_end() -> bool;

		void consume_spaces();
		auto is_whitespace(char c) -> bool;
		auto string_to_token(const str& string) -> token;
		auto string_to_number(const str& string) -> token;
	private:
		const str& m_source;
		char m_current_char;
		u64 m_index = 0;
	public:
		token curr;
		str curr_string;
		u64 curr_imm;
	};

	struct program {
		static program parse(const str& source);

		str to_string();
	private:
		str operand_to_string(inst::operand op, inst_spec::operand ty);
	public:

		arr<inst> instructions;
	};
} // namespace so

#endif // PROGRAM_H

