#ifndef CPU_PROGRAM_H
#define CPU_PROGRAM_H

#include "extensions/database.cuh"

typedef struct Program {
	Instruction* instructions;
	u32 size;
} Program;

i32 program_parse(Program* Program, arena* a, string source);
string program_to_string(Program* Program, arena* a);
u64 program_get_live_out(Program* Program);
u64 program_get_live_in(Program* Program);

#endif // #ifndef CPU_PROGRAM_H
