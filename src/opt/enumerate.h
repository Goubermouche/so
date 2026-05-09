#ifndef ENUMERATE_H
#define ENUMERATE_H

#include "int/instruction.cuh"
#include "opt/driver.cuh"

typedef struct opt_opcode_pool {
	int_opcode ops[OP_COUNT];
	u32 n_ops;
} opt_opcode_pool;

typedef struct opt_imm_pool {
	i64 vals[64];
	u32 n;
} opt_imm_pool;

typedef struct opt_candidate {
	int_inst code[SYNTH_PROG_LEN];
	u32 len;
} opt_candidate;

typedef struct opt_enumerator {
	const opt_opcode_pool* pool;
	const opt_imm_pool* imms;
	u64 live_in_mask;
	u64 live_out_mask;
	u32 max_scratch;
	arr<opt_candidate>* out;
	u64 cap;
} opt_enumerator;

opt_opcode_pool opt_build_opcode_pool(u32 ext_mask);
opt_imm_pool opt_build_default_imm_pool();

void opt_enum_backward(opt_enumerator* e, opt_candidate* cur, u32 prog_len, i32 idx, u64 demanded,
											 u64 used_scratch);
void opt_try_place(opt_enumerator* e, opt_candidate* cur, u32 prog_len, i32 idx, int_opcode op, u32 rd,
									 u32 rs1, u32 rs2_or_imm_idx, b32 is_imm, u64 demanded, u64 used_scratch);
void opt_enumerate(const opt_opcode_pool* pool, const opt_imm_pool* imms, u64 live_in_mask,
									 u64 live_out_mask, u32 prog_len, u32 max_scratch, arr<opt_candidate>* out,
									 u64 cap = (u64)-1);

#endif // #ifndef ENUMERATE_H
