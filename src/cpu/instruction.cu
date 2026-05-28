#include "cpu/instruction.cuh"

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

I8 instruction_shape_dst_slot(InstructionShape s) {
	return s == InstructionShape_None ? (I8)-1 : (I8)0;
}

I8 instruction_shape_src_slot(InstructionShape s) {
	switch(s) {
		case InstructionShape_RRR:
		case InstructionShape_RRI:
		case InstructionShape_RR: return 1;
		default: return -1;
	}
}

I8 instruction_shape_src2_slot(InstructionShape s) {
	return s == InstructionShape_RRR ? (I8)2 : (I8)-1;
}

S8 operand_to_string(Arena* a, InstructionOperand op, InstructionOperandType ty) {
	switch(ty) {
		case InstructionOperandType_Reg: return reg_name((U32)op.reg);
		case InstructionOperandType_Imm: return s8_make_fmt(a, "%lld", (I64)op.imm);
		default: return S8("?");
	}
}
