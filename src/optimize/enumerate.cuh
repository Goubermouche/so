#ifndef OPT_ENUMERATE_CUH
#define OPT_ENUMERATE_CUH

#include "extensions/database.cuh"

#define EnumImmPoolSize 64

typedef struct EnumProgram {
	Instruction code[MaxProgramLen];
} EnumProgram;

typedef struct EnumOpcodePool {
	InstructionOpcode ops[InstructionOpcode_Count];
	u32 n;
} EnumOpcodePool;

typedef struct EnumImmPool {
	i64 vals[EnumImmPoolSize];
	u32 n;
} EnumImmPool;

// TODO: unify with decode?
typedef struct EnumMeta {
	u16 op;
	u8 shape;
	u8 commutative;
	i8 dst_slot;
	i8 src_slot;
	i8 src2_slot;
	i8 imm_slot;
} EnumMeta;

// node in the backward-search frontier
typedef struct EnumState {
	Instruction code[MaxProgramLen];
	u64 demanded;			// registers that must be produced by earlier layers
	u64 used_scratch; // scratch regs already allocated by this branch
	i32 idx;
	u32 _pad;
} EnumState;

// layer constants passed to the kernels
typedef struct EnumLayer {
	const EnumMeta* meta;
	u32 n_meta;
	const i64* imms;
	u32 n_imms;
	u64 live_in_mask;
	u64 live_out_mask;
	u64 preserved_mask;
	u64 src_avail; // regs readable as sources at this layer
	u64 scratch_mask;
	u32 max_scratch;
	b32 is_last_layer; // last (bottom) layer emits EnumProgram, not EnumState
} EnumLayer;

typedef struct EnumOptions {
	const EnumOpcodePool* pool;
	const EnumImmPool* imms;
	u64 live_in_mask;
	u64 live_out_mask;
	u32 prog_len;
	u32 max_scratch;
	u64 cap;
} EnumOptions;

typedef struct Enum {
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
	EnumProgram* out_d_cands;
	u64 out_n_cands;
} Enum;

i32  enum_make(Enum* e, u64 batch_size);
void enum_free(Enum* e);
void enum_run(Enum* e, EnumOptions* opt);

void enum_make_meta_host(const EnumOpcodePool* pool, EnumMeta* out, u32* out_n);
void enum_make_opcode_pool(EnumOpcodePool* pool, u32 ext_mask);
void enum_make_imm_pool(EnumImmPool* pool);

#endif // OPT_ENUMERATE_CUH
