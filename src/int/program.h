#ifndef PROGRAM_H
#define PROGRAM_H

#include "int/instruction.cuh"

typedef enum int_token {
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
} int_token;

typedef struct int_program {
	int_inst* instructions;
	u32 size;
} int_program;

int_program int_parse(const str& source);
int_program int_dce(const int_program* program, u64 live_mask);
void int_program_free(const int_program* program);
str int_program_to_string(const int_program* program);
u64 int_program_live_outs(const int_program* program);
str int_operand_to_string(int_inst::operand op, int_inst_spec::operand ty);



const char* token_to_str(int_token tok);
b32 token_is_reg(int_token tok);
u64 token_to_reg_index(int_token tok);

struct tokenizer {
	tokenizer(const str& source);

	int_token next_tok();
	int_token next_tok_identifier();
	int_token next_tok_comment();
	int_token next_tok_string();
	int_token next_tok_char();

	char next_char();
	b32 is_at_end();

	void consume_spaces();
	b32 is_whitespace(char c);
	int_token string_to_token(const str& string);
	int_token string_to_number(const str& string);

private:
	const str& m_source;
	char m_current_char;
	u64 m_index = 0;

public:
	int_token curr;
	str curr_string;
	i64 curr_imm; // signed
};

int_opcode find_inst_op(const str& name, const int_inst_spec::operand* operands, u8 operand_count);

#endif // #ifndef PROGRAM_H
