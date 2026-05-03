#ifndef PROGRAM_H
#define PROGRAM_H

#include "int/instruction.cuh"

namespace so {
	enum token {
		TOK_UNKNOWN = 0,

		TOK_IDENTIFIER,
		TOK_NUMBER,

		// regs
		TOK_REG_RAX,
		TOK_REG_RBX,
		TOK_REG_RCX,
		TOK_REG_RDX,
		TOK_REG_RSI,
		TOK_REG_RDI,
		TOK_REG_RBP,
		TOK_REG_RSP,
		TOK_REG_R8,
		TOK_REG_R9,
		TOK_REG_R10,
		TOK_REG_R11,
		TOK_REG_R12,
		TOK_REG_R13,
		TOK_REG_R14,
		TOK_REG_R15,

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

	const char* token_to_str(token tok);
	bool token_is_reg(token tok);
	u64 token_to_reg_index(token tok);

	struct tokenizer {
		tokenizer(const str& source);

		token next_tok();
		token next_tok_identifier();
		token next_tok_comment();
		token next_tok_string();
		token next_tok_char();

		char next_char();
		bool is_at_end();

		void consume_spaces();
		bool is_whitespace(char c);
		token string_to_token(const str& string);
		token string_to_number(const str& string);
	private:
		const str& m_source;
		char m_current_char;
		u64 m_index = 0;
	public:
		token curr;
		str curr_string;
		u64 curr_imm;
	};

	opcode find_inst_op(const str& name, const inst_spec::operand* operands, u8 operand_count);

	struct program {
		static program parse(const str& source);
		static program dce(const inst* prog, u32 prog_len, u64 live_mask);

		str to_string() const;
		u64 live_outs() const;
	private:
		str operand_to_string(inst::operand op, inst_spec::operand ty) const;
	public:
		arr<inst> instructions;
	};
} // namespace so

#endif // #ifndef PROGRAM_H

