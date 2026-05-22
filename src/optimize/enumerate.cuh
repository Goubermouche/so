#ifndef OPT_ENUMERATE_CUH
#define OPT_ENUMERATE_CUH

#include "extensions/database.cuh"

#define EnumImmPoolSize 64

typedef struct EnumProgram {
	Instruction code[MaxProgramLen];
} EnumProgram;

typedef struct EnumOpcodePool {
	InstructionOpcode ops[InstructionOpcode_Count];
	U32 n;
} EnumOpcodePool;

typedef struct EnumImmPool {
	I64 vals[EnumImmPoolSize];
	U32 n;
} EnumImmPool;

// TODO: unify with decode?
typedef struct EnumMeta {
	U16 op;
	U8 shape;
	U8 commutative;
	I8 dst_slot;
	I8 src_slot;
	I8 src2_slot;
	I8 imm_slot;
} EnumMeta;

// node in the backward-search frontier
typedef struct EnumState {
	Instruction code[MaxProgramLen];
	U64 demanded;			// registers that must be produced by earlier layers
	U64 used_scratch; // scratch regs already allocated by this branch
	I32 idx;
	U32 _pad;
} EnumState;

// layer constants passed to the kernels
typedef struct EnumLayer {
	const EnumMeta* meta;
	U32 n_meta;
	const I64* imms;
	U32 n_imms;
	U64 live_in_mask;
	U64 live_out_mask;
	U64 preserved_mask;
	U64 src_avail; // regs readable as sources at this layer
	U64 scratch_mask;
	U32 max_scratch;
	B32 is_last_layer; // last (bottom) layer emits EnumProgram, not EnumState
} EnumLayer;

typedef struct EnumOptions {
	const EnumOpcodePool* pool;
	const EnumImmPool* imms;
	U64 live_in_mask;
	U64 live_out_mask;
	U32 prog_len;
	U32 max_scratch;
	U64 cap;
} EnumOptions;

typedef struct Enum {
	void* d_meta;
	U32 n_meta;
	void* d_imms;
	U32 n_imms_cap;
	U64 capacity; // max simultaneous frontier / emitted-candidate slots
	void* d_front_a;
	void* d_front_b;
	void* d_counts;
	void* d_offsets;
	void* d_out;
	void* d_scan_tmp;
	U64 scan_tmp_bytes;
	// output
	EnumProgram* out_d_cands;
	U64 out_n_cands;
} Enum;

I32  enum_make(Enum* e, U64 batch_size);
void enum_free(Enum* e);
void enum_run(Enum* e, EnumOptions* opt);

void enum_make_meta_host(const EnumOpcodePool* pool, EnumMeta* out, U32* out_n);
void enum_make_opcode_pool(EnumOpcodePool* pool, U32 ext_mask);
void enum_make_imm_pool(EnumImmPool* pool);

#endif // OPT_ENUMERATE_CUH
