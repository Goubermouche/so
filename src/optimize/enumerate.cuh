#ifndef OPT_ENUMERATE_CUH
#define OPT_ENUMERATE_CUH

#include "cpu/instruction.cuh"
#include "optimize/filter.cuh"

#define OPT_IMM_POOL_CAP 64

namespace sup {

typedef struct opt_program {
	inst code[OPT_PROGRAM_LEN];
} opt_program;

typedef struct opt_opcode_pool {
	opcode ops[OP_COUNT];
	u32 n;
} opt_opcode_pool;

typedef struct opt_imm_pool {
	i64 vals[OPT_IMM_POOL_CAP];
	u32 n;
} opt_imm_pool;

typedef struct opt_enum_cfg {
	const opt_opcode_pool* pool;
	const opt_imm_pool* imms;
	u64 live_in_mask;
	u64 live_out_mask;
	u32 prog_len;
	u32 max_scratch;
	u64 cap;
} opt_enum_cfg;

typedef enum {
	OPT_SHAPE_RRR = 0, // dst, reg, reg
	OPT_SHAPE_RRI = 1, // dst, reg, imm
	OPT_SHAPE_RI = 2,	 // dst, imm
	OPT_SHAPE_RR = 3,	 // dst, reg
} opt_shape;

// TODO: unify
typedef struct opt_meta {
	u16 op;
	u8 shape;
	u8 commutative;
	i8 dst_slot;
	i8 src_slot;
	i8 src2_slot;
	i8 imm_slot;
} opt_meta;

// node in the backward-search frontier
typedef struct opt_state {
	inst code[OPT_PROGRAM_LEN];
	u64 demanded;			// registers that must be produced by earlier layers
	u64 used_scratch; // scratch regs already allocated by this branch
	i32 idx;
	u32 _pad;
} opt_state;

// layer constants passed to the kernels
typedef struct opt_layer_ctx {
	const opt_meta* meta;
	u32 n_meta;
	const i64* imms;
	u32 n_imms;
	u64 live_in_mask;
	u64 live_out_mask;
	u64 preserved_mask;
	u64 src_avail; // regs readable as sources at this layer
	u64 scratch_mask;
	u32 max_scratch;
	b32 is_last_layer; // last (bottom) layer emits opt_program, not opt_state
} opt_layer_ctx;

typedef struct opt_enum_ctx {
	void* d_meta;
	u32 n_meta;
	void* d_imms;
	u32 n_imms_cap;
	u64 capacity; // max simultaneous frontier / emitted-candidate slots
	void* d_front_a;
	void* d_front_b;
	void* d_counts;
	void* d_offsets;
	void* d_out;
	void* d_scan_tmp;
	size_t scan_tmp_bytes;
	// output
	opt_program* out_d_cands;
	u64 out_n_cands;
} opt_enum_ctx;

i32 opt_enum_make(opt_enum_ctx* ctx, u64 batch_size);
void opt_enum_ctx_free(opt_enum_ctx* ctx);
void opt_enumerate(opt_enum_ctx* ctx, const opt_enum_cfg* cfg);
void opt_build_meta_host(const opt_opcode_pool* pool, opt_meta* out, u32* out_n);

opt_opcode_pool opt_build_opcode_pool(u32 ext_mask);
opt_imm_pool opt_build_imm_pool();
} // namespace sup

#endif // OPT_ENUMERATE_CUH
