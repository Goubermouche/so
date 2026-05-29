#ifndef EXT_RUN_CUH
#define EXT_RUN_CUH

#include "cpu/instruction.cuh"

// sign-extend the low 32 bits of value to 64 bits
HostDevice I64 ext_rv_sext32(U64 value) { return (I64)(I32)(U32)value; }

HostDevice void ext_rv_wr(U64 regs[32], U32 destination, U64 value) {
	regs[destination] = value;
	regs[0] = 0; // pin x0
}

HostDevice U64 ext_run_inst_cheap(InstructionOpcode op, U64 a, U64 b, U64 imm) {
	U32 sh_b = (U32)(b & 0x3F);
	U32 sh_i = (U32)(imm & 0x3F);
	U32 sh_b5 = (U32)(b & 0x1F);
	U32 sh_i5 = (U32)(imm & 0x1F);
	U32 a32 = (U32)a;
	U32 b32 = (U32)b;
	U32 i32 = (U32)imm;

	switch(op) {
		case InstructionOpcode_Add: return a + b;
		case InstructionOpcode_Sub: return a - b;
		case InstructionOpcode_Sll: return a << sh_b;
		case InstructionOpcode_Slt: return ((I64)a < (I64)b) ? 1ull : 0ull;
		case InstructionOpcode_Sltu: return (a < b) ? 1ull : 0ull;
		case InstructionOpcode_Xor: return a ^ b;
		case InstructionOpcode_Srl: return a >> sh_b;
		case InstructionOpcode_Sra: return (U64)((I64)a >> sh_b);
		case InstructionOpcode_Or: return a | b;
		case InstructionOpcode_And: return a & b;
		case InstructionOpcode_Addi: return a + imm;
		case InstructionOpcode_Slti: return ((I64)a < (I64)imm) ? 1ull : 0ull;
		case InstructionOpcode_Sltiu: return (a < imm) ? 1ull : 0ull;
		case InstructionOpcode_Xori: return a ^ imm;
		case InstructionOpcode_Ori: return a | imm;
		case InstructionOpcode_Andi: return a & imm;
		case InstructionOpcode_Slli: return a << sh_i;
		case InstructionOpcode_Srli: return a >> sh_i;
		case InstructionOpcode_Srai: return (U64)((I64)a >> sh_i);
		// lui: RI-shape (imm is in operands[1], not rs1)
		case InstructionOpcode_Lui: return (U64)(I64)(I32)((U32)imm << 12);
		case InstructionOpcode_Addiw: return (U64)(I64)(I32)(a32 + i32);
		case InstructionOpcode_Slliw: return (U64)(I64)(I32)(a32 << sh_i5);
		case InstructionOpcode_Srliw: return (U64)(I64)(I32)(a32 >> sh_i5);
		case InstructionOpcode_Sraiw: return (U64)(I64)((I32)a32 >> sh_i5);
		case InstructionOpcode_Addw: return (U64)(I64)(I32)(a32 + b32);
		case InstructionOpcode_Subw: return (U64)(I64)(I32)(a32 - b32);
		case InstructionOpcode_Sllw: return (U64)(I64)(I32)(a32 << sh_b5);
		case InstructionOpcode_Srlw: return (U64)(I64)(I32)(a32 >> sh_b5);
		case InstructionOpcode_Sraw: return (U64)(I64)((I32)a32 >> sh_b5);
		default: return 0;
	}
}

HostDevice U64 ext_run_inst_mul(InstructionOpcode op, U64 a, U64 b) {
	switch(op) {
		case InstructionOpcode_Mul: return a * b;
		case InstructionOpcode_Mulh: {
			__int128 sa = (__int128)(I64)a;
			__int128 sb = (__int128)(I64)b;
			return (U64)(I64)((sa * sb) >> 64);
		}
		case InstructionOpcode_Mulhsu: {
			__int128 sa = (__int128)(I64)a;
			__int128 ub = (__int128)(unsigned __int128)b;
			return (U64)(I64)((sa * ub) >> 64);
		}
		case InstructionOpcode_Mulhu: {
			unsigned __int128 ua = (unsigned __int128)a;
			unsigned __int128 ub = (unsigned __int128)b;
			return (U64)((ua * ub) >> 64);
		}
		case InstructionOpcode_Mulw: {
			I32 r = (I32)a * (I32)b;
			return (U64)(I64)r;
		}
		default: return 0;
	}
}

HostDevice U64 ext_run_inst_div(InstructionOpcode op, U64 a, U64 b) {
	switch(op) {
		case InstructionOpcode_Div: {
			I64 sa = (I64)a, sb = (I64)b;
			if(sb == 0) return (U64)(I64)-1;
			if(sa == (I64)0x8000000000000000ULL && sb == -1) return (U64)sa;
			return (U64)(sa / sb);
		}
		case InstructionOpcode_Divu: return (b == 0) ? (U64)-1 : (a / b);
		case InstructionOpcode_Rem: {
			I64 sa = (I64)a, sb = (I64)b;
			if(sb == 0) return (U64)sa;
			if(sa == (I64)0x8000000000000000ULL && sb == -1) return 0;
			return (U64)(sa % sb);
		}
		case InstructionOpcode_Remu: return (b == 0) ? a : (a % b);
		case InstructionOpcode_Divw: {
			I32 sa = (I32)a, sb = (I32)b;
			I32 r;
			if(sb == 0)
				r = -1;
			else if(sa == (I32)0x80000000 && sb == -1)
				r = sa;
			else
				r = sa / sb;
			return (U64)(I64)r;
		}
		case InstructionOpcode_Divuw: {
			U32 ua = (U32)a, ub = (U32)b;
			return (U64)(I64)(I32)(ub == 0 ? (U32)-1 : ua / ub);
		}
		case InstructionOpcode_Remw: {
			I32 sa = (I32)a, sb = (I32)b;
			I32 r;
			if(sb == 0)
				r = sa;
			else if(sa == (I32)0x80000000 && sb == -1)
				r = 0;
			else
				r = sa % sb;
			return (U64)(I64)r;
		}
		case InstructionOpcode_Remuw: {
			U32 ua = (U32)a, ub = (U32)b;
			return (U64)(I64)(I32)(ub == 0 ? ua : ua % ub);
		}
		default: return 0;
	}
}

HostDevice U64 ext_run_inst_dispatch(
	InstructionOpcode op,
	U64 op_1,
	U64 op_2,
	U64 imm,
	InstructionOpcodeClass op_class,
	B32 has_mul,
	B32 has_div
) {
	// dispatch to the right runner based on op class and warp flags
	if(has_mul && op_class == InstructionOpcodeClass_Mul) return ext_run_inst_mul(op, op_1, op_2);
	if(has_div && op_class == InstructionOpcodeClass_Div) return ext_run_inst_div(op, op_1, op_2);
	return ext_run_inst_cheap(op, op_1, op_2, imm);
}

HostDevice InstructionOpcodeClass ext_op_class(InstructionOpcode op) {
	switch(op) {
		case InstructionOpcode_Mul:
		case InstructionOpcode_Mulh:
		case InstructionOpcode_Mulhsu:
		case InstructionOpcode_Mulhu:
		case InstructionOpcode_Mulw: return InstructionOpcodeClass_Mul;
		case InstructionOpcode_Div:
		case InstructionOpcode_Divu:
		case InstructionOpcode_Rem:
		case InstructionOpcode_Remu:
		case InstructionOpcode_Divw:
		case InstructionOpcode_Divuw:
		case InstructionOpcode_Remw:
		case InstructionOpcode_Remuw: return InstructionOpcodeClass_Div;
		default: return InstructionOpcodeClass_Cheap;
	}
}

HostDevice B32 ext_run_inst(U64 regs[32], Instruction* inst) {
	U32 destination;
	U64 op_1;
	U64 op_2;
	U64 imm;

	if(inst->op == InstructionOpcode_Lui) {
		// RI
		destination = (U32)inst->operands[0].reg;
		op_1 = 0;
		op_2 = 0;
		imm = inst->operands[1].imm;
	} else {
		// RRR / RRI
		destination = (U32)inst->operands[0].reg;
		op_1 = regs[inst->operands[1].reg & 31];
		op_2 = regs[inst->operands[2].reg & 31];
		imm = inst->operands[2].imm;
	}

	InstructionOpcodeClass op_class = ext_op_class(inst->op);
	U64 value = ext_run_inst_dispatch(inst->op, op_1, op_2, imm, op_class, true, true);
	ext_rv_wr(regs, destination, value);
	return true;
}

HostDevice CpuState ext_run_program(Program* prog, CpuState* in) {
	CpuState out = *in;
	out.regs[0] = 0;

	for(U32 i = 0; i < prog->size; ++i) {
		Instruction* inst = &prog->instructions[i];

		if(inst->op == InstructionOpcode_Nop) { continue; }
		ext_run_inst(out.regs, inst);
	}

	return out;
}

#endif // #ifndef EXT_RUN_CUH
