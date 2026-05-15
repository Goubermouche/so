#ifndef OPT_ENUMERATE_CUH
#define OPT_ENUMERATE_CUH

#include "cpu/instruction.cuh"
#include "optimize/filter.cuh"

typedef struct opt_program {
	cpu_inst code[SYNTH_PROG_LEN];
} opt_program;

typedef struct opt_opcode_pool {
	cpu_opcode ops[OP_COUNT];
	u32 n_ops;
} opt_opcode_pool;

typedef struct opt_imm_pool {
	i64 vals[64]; // TODO
	u32 n;
} opt_imm_pool;

typedef struct opt_enum_config {
	const opt_opcode_pool* pool;
	const opt_imm_pool* imms;
	u64 live_in_mask;
	u64 live_out_mask;
	u32 prog_len;
	u32 max_scratch;
} opt_enum_config;

// TODO: unify
typedef struct opt_op_meta {
	u16 op;
	u8 shape;
	u8 commutative;
	i8 dst_slot;
	i8 src_slot;
	i8 src2_slot;
	i8 imm_slot;
} opt_op_meta;

// TODO: unify
typedef enum {
	OPT_SHAPE_RRR = 0,
	OPT_SHAPE_RRI = 1,
	OPT_SHAPE_RI = 2,
	OPT_SHAPE_RR = 3,
} opt_shape;

typedef struct opt_state {
	cpu_inst code[SYNTH_PROG_LEN];
	u64 demanded;
	u64 used_scratch;
	i32 idx;
	u32 _pad;
} opt_state;

typedef struct opt_enum_ctx {
	void* d_meta;
	u32 n_meta;
	void* d_imms;
	u32 n_imms_cap;
	u64 capacity;
	void* d_front_a;
	void* d_front_b;
	void* d_counts;
	void* d_offsets;
	void* d_out;
	void* d_scan_tmp;
	size_t scan_tmp_bytes;
} opt_enum_ctx;

i32 opt_enum_make(opt_enum_ctx* ec, u64 batch_size);
void opt_enum_ctx_free(opt_enum_ctx* ec);

opt_opcode_pool opt_build_opcode_pool(u32 ext_mask);
opt_imm_pool opt_build_imm_pool();
void opt_enumerate(opt_enum_ctx* ec, const opt_enum_config* cfg, u64 cap,
									 opt_program** out_d_cands, u64* out_n_cands);

#endif // #ifndef OPT_ENUMERATE_CUH
