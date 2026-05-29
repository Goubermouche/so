#include "extensions/run.cuh"

B32 ext_run_inst(U64 regs[32], Instruction* inst) {
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

	InstructionOpcodeClass op_class = instruction_opcode_class(inst->op);
	U64 value = ext_run_inst_dispatch(inst->op, op_1, op_2, imm, op_class, true, true);
	// write result
	regs[destination] = value;
	regs[0] = 0; // pin x0
	return true;
}

CpuState ext_run_program(Program* prog, CpuState* in) {
	CpuState out = *in;
	out.regs[0] = 0;

	for(U32 i = 0; i < prog->size; ++i) {
		Instruction* inst = &prog->instructions[i];

		if(inst->op == InstructionOpcode_Nop) { continue; }
		ext_run_inst(out.regs, inst);
	}

	return out;
}