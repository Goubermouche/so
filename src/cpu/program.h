#ifndef CPU_PROGRAM_H
#define CPU_PROGRAM_H

#include "cpu/instruction.cuh"

typedef struct cpu_program {
	cpu_inst* instructions;
	u32 size;
} cpu_program;

cpu_program cpu_program_parse(str source);
cpu_program cpu_program_dce(const cpu_program* program, u64 live_mask);

void cpu_program_free(const cpu_program* program);
str cpu_program_to_str(arena* a, const cpu_program* program);
u64 cpu_program_live_outs(const cpu_program* program);

#endif // #ifndef CPU_PROGRAM_H
