#ifndef PROGRAM_H
#define PROGRAM_H

#include "int/instruction.cuh"

namespace sup {
	enum token {
		TOK_UNKNOWN = 0,

		TOK_IDENTIFIER,
		TOK_NUMBER,

		// regs
		TOK_REG_X0,
		TOK_REG_X1,
		TOK_REG_X2,
		TOK_REG_X3,
		TOK_REG_X4,
		TOK_REG_X5,
		TOK_REG_X6,
		TOK_REG_X7,
		TOK_REG_X8,
		TOK_REG_X9,
		TOK_REG_X10,
		TOK_REG_X11,
		TOK_REG_X12,
		TOK_REG_X13,
		TOK_REG_X14,
		TOK_REG_X15,
		TOK_REG_X16,
		TOK_REG_X17,
		TOK_REG_X18,
		TOK_REG_X19,
		TOK_REG_X20,
		TOK_REG_X21,
		TOK_REG_X22,
		TOK_REG_X23,
		TOK_REG_X24,
		TOK_REG_X25,
		TOK_REG_X26,
		TOK_REG_X27,
		TOK_REG_X28,
		TOK_REG_X29,
		TOK_REG_X30,
		TOK_REG_X31,

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
	b32 token_is_reg(token tok);
	u64 token_to_reg_index(token tok);

	struct tokenizer {
		tokenizer(const str& source);

		token next_tok();
		token next_tok_identifier();
		token next_tok_comment();
		token next_tok_string();
		token next_tok_char();

		char next_char();
		b32 is_at_end();

		void consume_spaces();
		b32 is_whitespace(char c);
		token string_to_token(const str& string);
		token string_to_number(const str& string);
	private:
		const str& m_source;
		char m_current_char;
		u64 m_index = 0;
	public:
		token curr;
		str curr_string;
		i64 curr_imm; // signed
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
} // namespace sup

#endif // #ifndef PROGRAM_H

