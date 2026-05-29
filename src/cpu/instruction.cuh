#ifndef INSTRUCTION_CUH
#define INSTRUCTION_CUH

#include "cpu/cpu.cuh"

typedef union InstructionOperand {
	Reg reg;
	U64 imm;
} InstructionOperand;

typedef U8 InstructionOperandType;
typedef enum InstructionOperandTypeEnum {
	InstructionOperandType_None = 0,
	InstructionOperandType_Reg,
	InstructionOperandType_Imm,
} InstructionOperandTypeEnum;

typedef U32 InstructionOpcode; // enum in ext

typedef struct Instruction {
	InstructionOpcode op;
	InstructionOperand operands[4];
} Instruction;

typedef struct InstructionInfo {
	S8 name;
	InstructionOperandType operands[4];
	InstructionOpcode op;
	I8 dst_slot;
	I8 src_slot;
	I8 src2_slot;
	U32 ext;
	U8 commutative;
	U8 operand_count;
} InstructionInfo;

typedef U8 InstructionShape;
typedef enum InstructionShapeEnum {
	InstructionShape_None = 0, // nop
	InstructionShape_RRR,			 // rd, rs1, rs2
	InstructionShape_RRI,			 // rd, rs1, imm
	InstructionShape_RR,			 // rd, rs1
	InstructionShape_RI,			 // rd, imm
} InstructionShapeEnum;

InstructionOperandType instruction_shape_op0(InstructionShape s);
InstructionOperandType instruction_shape_op1(InstructionShape s);
InstructionOperandType instruction_shape_op2(InstructionShape s);

I8 instruction_shape_dst_slot(InstructionShape s);
I8 instruction_shape_src_slot(InstructionShape s);
I8 instruction_shape_src2_slot(InstructionShape s);

S8 operand_to_string(Arena* a, InstructionOperand op, InstructionOperandType ty);

// TODO: get rid of Instruction and replace with this?
// instruction packing for gpu work:
// unpacked version of PackedInstruction for easier manipulation
typedef struct UnpackedInstruction {
	U32 parent_local_id; // [0-31]
	U32 op_idx;          // [32-39]
	U32 rd;              // [40-44]
	U32 rs1;             // [45-49]
	U32 rs2_or_imm_idx;  // [50-57]
	B32 is_imm;          // [58]
} UnpackedInstruction;

typedef U64 PackedInstruction;

HostDevice PackedInstruction instruction_pack(UnpackedInstruction inst) {
	PackedInstruction packed = (U64)inst.parent_local_id & 0xFFFFFFFFull;
	packed |= ((U64)inst.op_idx & 0xFFull) << 32;
	packed |= ((U64)inst.rd & 0x1Full) << 40;
	packed |= ((U64)inst.rs1 & 0x1Full) << 45;
	packed |= ((U64)inst.rs2_or_imm_idx & 0xFFull) << 50;
	packed |= ((U64)(inst.is_imm ? 1u : 0u)) << 58;
	return packed;
}

HostDevice UnpackedInstruction instruction_unpack(PackedInstruction packed) {
	UnpackedInstruction inst;
	inst.parent_local_id = (U32)(packed & 0xFFFFFFFFull);
	inst.op_idx = (U32)((packed >> 32) & 0xFFull);
	inst.rd = (U32)((packed >> 40) & 0x1Full);
	inst.rs1 = (U32)((packed >> 45) & 0x1Full);
	inst.rs2_or_imm_idx = (U32)((packed >> 50) & 0xFFull);
	inst.is_imm = (B32)((packed >> 58) & 0x1ull);
	return inst;
}

#endif // #ifndef INSTRUCTION_CUH
