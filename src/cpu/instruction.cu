#include "cpu/instruction.cuh"
#include "util/device.h"

InstructionOperandType instruction_shape_op0(InstructionShape s) {
	return s == InstructionShape_None ? InstructionOperandType_None : InstructionOperandType_Reg;
}

InstructionOperandType instruction_shape_op1(InstructionShape s) {
	switch(s) {
		case InstructionShape_RRR:
		case InstructionShape_RRI:
		case InstructionShape_RR: return InstructionOperandType_Reg;
		case InstructionShape_RI: return InstructionOperandType_Imm;
		default: return InstructionOperandType_None;
	}
}

InstructionOperandType instruction_shape_op2(InstructionShape s) {
	switch(s) {
		case InstructionShape_RRR: return InstructionOperandType_Reg;
		case InstructionShape_RRI: return InstructionOperandType_Imm;
		default: return InstructionOperandType_None;
	}
}

i8 instruction_shape_dst_slot(InstructionShape s) {
	return s == InstructionShape_None ? (i8)-1 : (i8)0;
}

i8 instruction_shape_src_slot(InstructionShape s) {
	switch(s) {
		case InstructionShape_RRR:
		case InstructionShape_RRI:
		case InstructionShape_RR: return 1;
		default: return -1;
	}
}

i8 instruction_shape_src2_slot(InstructionShape s) {
	return s == InstructionShape_RRR ? (i8)2 : (i8)-1;
}

string operand_to_string(arena& a, InstructionOperand op, InstructionOperandType ty) {
	switch(ty) {
		case InstructionOperandType_Reg: return reg_name((u32)op.reg);
		case InstructionOperandType_Imm: return string::format(a, "%lld", (i64)op.imm);
		default: return "?";
	}
}