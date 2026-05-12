#ifndef OPT_ENUMERATE_H
#define OPT_ENUMERATE_H

#include "cpu/instruction.cuh"
#include "opt/driver.cuh"

typedef struct opt_opcode_pool {
	cpu_opcode ops[OP_COUNT];
	u32 n_ops;
} opt_opcode_pool;

typedef struct opt_imm_pool {
	i64 vals[64];
	u32 n;
} opt_imm_pool;

typedef struct opt_candidate {
	cpu_inst code[SYNTH_PROG_LEN];
	u32 len;
} opt_candidate;

ARR_DECL(opt_candidate, opt_candidate_arr)

typedef struct opt_enumerator {
	const opt_opcode_pool* pool;
	const opt_imm_pool* imms;
	u64 live_in_mask;
	u64 live_out_mask;
	u32 max_scratch;
	u32 prog_len;
	opt_candidate_arr* out;
	u64 cap;
} opt_enumerator;

typedef struct opt_enum_state {
	opt_candidate* cur;
	i32 idx;
	u64 demanded;
	u64 used_scratch;
} opt_enum_state;

typedef struct opt_place_attempt {
	cpu_opcode op;
	u32 rd;
	u32 rs1;
	u32 rs2_or_imm_idx;
	b32 is_imm;
} opt_place_attempt;

typedef struct opt_enum_config {
	const opt_opcode_pool* pool;
	const opt_imm_pool* imms;
	u64 live_in_mask;
	u64 live_out_mask;
	u32 prog_len;
	u32 max_scratch;
} opt_enum_config;

opt_opcode_pool opt_build_opcode_pool(u32 ext_mask);
opt_imm_pool opt_build_default_imm_pool();

void opt_enum_backward(opt_enumerator* e, opt_enum_state* s);
void opt_try_place(opt_enumerator* e, opt_enum_state* s, const opt_place_attempt* a);
void opt_enumerate(const opt_enum_config* cfg, opt_candidate_arr* out, u64 cap);

#endif // #ifndef OPT_ENUMERATE_H
