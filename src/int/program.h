#ifndef PROGRAM_H
#define PROGRAM_H

#include "int/instruction.cuh"

typedef struct int_program {
	int_inst* instructions;
	u32 size;
} int_program;

int_program int_parse(str source);
int_program int_dce(const int_program* program, u64 live_mask);

void int_program_free(const int_program* program);
str int_program_to_string(arena* a, const int_program* program);
u64 int_program_live_outs(const int_program* program);

#endif // #ifndef PROGRAM_H
