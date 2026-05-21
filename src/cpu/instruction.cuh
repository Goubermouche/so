#ifndef INSTRUCTION_CUH
#define INSTRUCTION_CUH

#include "cpu/cpu.cuh"
#include "util/string.h"

typedef union InstructionOperand {
	Reg reg;
	u64 imm;
} InstructionOperand;

typedef enum InstructionOperandType {
	InstructionOperandType_None = 0,
	InstructionOperandType_Reg,
	InstructionOperandType_Imm,
} InstructionOperandType;

typedef u32 InstructionOpcode; // enum in ext

typedef struct Instruction {
	InstructionOpcode op;
	InstructionOperand operands[4];
} Instruction;

typedef struct InstructionInfo {
	const c8* name;
	InstructionOperandType operands[4];
	InstructionOpcode op;
	i8 dst_slot;
	i8 src_slot;
	i8 src2_slot;
	u32 ext;
	u8 commutative;
	u8 operand_count;
} InstructionInfo;

typedef enum InstructionShape {
	InstructionShape_None = 0, // nop
	InstructionShape_RRR,			 // rd, rs1, rs2
	InstructionShape_RRI,			 // rd, rs1, imm
	InstructionShape_RR,			 // rd, rs1
	InstructionShape_RI,			 // rd, imm
} InstructionShape;

InstructionOperandType instruction_shape_op0(InstructionShape s);
InstructionOperandType instruction_shape_op1(InstructionShape s);
InstructionOperandType instruction_shape_op2(InstructionShape s);

i8 instruction_shape_dst_slot(InstructionShape s);
i8 instruction_shape_src_slot(InstructionShape s);
i8 instruction_shape_src2_slot(InstructionShape s);

string operand_to_string(arena* a, InstructionOperand op, InstructionOperandType ty);

#endif // #ifndef INSTRUCTION_CUH
