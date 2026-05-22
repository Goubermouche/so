#ifndef CPU_PROGRAM_H
#define CPU_PROGRAM_H

#include "extensions/database.cuh"

typedef struct Program {
	Instruction* instructions;
	U32 size;
} Program;

I32 program_parse(Program* Program, Arena* a, Str source);
Str program_to_string(Program* Program, Arena* a);
U64 program_get_live_out(Program* Program);
U64 program_get_live_in(Program* Program);

#endif // #ifndef CPU_PROGRAM_H
