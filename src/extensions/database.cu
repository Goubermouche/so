#include "database.cuh"

InstructionDB instruction_db_host;
__constant__ InstructionDB instruction_db_dev;

__device__ const InstructionInfo* instruction_db_find_info_dev(InstructionOpcode op) {
	return &instruction_db_dev.row[op];
}

static void instruction_db_row(InstructionDB* d, InstructionOpcode op, const c8* name,
															 InstructionShape shape, u8 commutative, u32 ext_bit) {
	InstructionInfo* r = &d->row[op];
	r->name = name;
	r->operands[0] = instruction_shape_op0(shape);
	r->operands[1] = instruction_shape_op1(shape);
	r->operands[2] = instruction_shape_op2(shape);
	r->operands[3] = InstructionOperandType_None;
	r->op = op;
	r->dst_slot = instruction_shape_dst_slot(shape);
	r->src_slot = instruction_shape_src_slot(shape);
	r->src2_slot = instruction_shape_src2_slot(shape);
	r->ext = ext_bit;
	r->commutative = commutative;
	switch(shape) {
		case InstructionShape_None: r->operand_count = 0; break;
		case InstructionShape_RRR: r->operand_count = 3; break;
		case InstructionShape_RRI: r->operand_count = 3; break;
		case InstructionShape_RR: r->operand_count = 2; break;
		case InstructionShape_RI: r->operand_count = 2; break;
	}
}

static void InstructionDatabase_build_host(InstructionDB* d) {
	memset(d, 0, sizeof(*d));

#define X(tag, mn, shape, comm)                                                                    \
	instruction_db_row(d, InstructionOpcode_##tag, mn, shape, (u8)(comm), ExtRV32I);
	ExtensionsRV32IOpcodes(X)
#undef X
#define X(tag, mn, shape, comm)                                                                    \
	instruction_db_row(d, InstructionOpcode_##tag, mn, shape, (u8)(comm), ExtRV64I);
		ExtensionsRV64IOpcodes(X)
#undef X
#define X(tag, mn, shape, comm)                                                                    \
	instruction_db_row(d, InstructionOpcode_##tag, mn, shape, (u8)(comm), ExtRV32M);
			ExtensionsRV32MOpcodes(X)
#undef X
#define X(tag, mn, shape, comm)                                                                    \
	instruction_db_row(d, InstructionOpcode_##tag, mn, shape, (u8)(comm), ExtRV64M);
				ExtensionsRV64MOpcodes(X)
#undef X

		// NOP
		InstructionInfo* nop = &d->row[InstructionOpcode_Nop];
	nop->name = "nop";
	nop->operands[0] = InstructionOperandType_None;
	nop->operands[1] = InstructionOperandType_None;
	nop->operands[2] = InstructionOperandType_None;
	nop->operands[3] = InstructionOperandType_None;
	nop->op = InstructionOpcode_Nop;
	nop->dst_slot = -1;
	nop->src_slot = -1;
	nop->src2_slot = -1;
	nop->ext = ExtRV32I;
	nop->commutative = 0;
}

InstructionOpcode instruction_db_find(string name, const InstructionOperandType* ops, u8 op_cnt) {
	for(u32 i = 0; i < (u32)InstructionOpcode_Count; ++i) {
		const InstructionInfo* info = &instruction_db_host.row[i];
		if(name != info->name) { continue; }
		if(info->operand_count != op_cnt) { continue; }
		b32 ok = true;

		for(u8 k = 0; k < op_cnt; ++k) {
			if(info->operands[k] != ops[k]) {
				ok = false;
				break;
			}
		}

		if(ok) { return (InstructionOpcode)i; }
	}

	return InstructionOpcode_Count; // sentinel: no match
}

void instruction_db_load() {
	InstructionDatabase_build_host(&instruction_db_host);
	check_cuda(cudaMemcpyToSymbol(instruction_db_dev, &instruction_db_host, sizeof(InstructionDB)),
						 "instruction_db_load");
}
