#ifndef OPT_ENUMERATE_CUH
#define OPT_ENUMERATE_CUH

#include "cpu/program.h"

#define EnumImmPoolSize 64
#define EnumMaxMeta 256

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
typedef struct EnumStateHeader {
	U64 demanded;			// registers that must be produced by earlier layers
	U64 used_scratch; // scratch regs already allocated by this branch
	I32 idx;
	U32 _pad;
} EnumStateHeader;

typedef struct EnumStateCode {
	Instruction code[MaxProgramLen];
} EnumStateCode;

// layer constants passed to the kernels
typedef struct EnumLayer {
	U32 n_meta;
	U32 n_imms;
	U64 live_in_mask;
	U64 live_out_mask;
	U64 preserved_mask;
	U64 src_avail; // regs readable as sources at this layer
	U64 scratch_mask;
	U32 max_scratch;
	B32 is_last_layer; // last (bottom) layer emits tuples, not new states
} EnumLayer;

typedef struct EnumOptions {
	EnumOpcodePool* pool;
	EnumImmPool* imms;
	U64 live_in_mask;
	U64 live_out_mask;
	U32 prog_len;
	U32 max_scratch;
	U64 cap;
} EnumOptions;

typedef struct Enum {
	U32 n_meta;
	U32 n_imms_cap;
	U32 n_imms;
	U64 capacity; // max simultaneous frontier slots
	void* d_front_a_hdr;
	void* d_front_a_code;
	void* d_front_b_hdr;
	void* d_front_b_code;
	void* d_counts;
	void* d_offsets;
	void* d_tuples; // last-layer packed (op, rd, rs1, rs2/imm, parent) U64 per cand
	void* d_scan_tmp;
	U64 scan_tmp_bytes;
	// last layer
	B32 last_layer_ready;
	void* d_last_front_hdr;	 // parent headers
	void* d_last_front_code; // parent codes
	U64 last_layer_n_front;
	U64 last_layer_cursor;
	U64 last_layer_cap;
	EnumLayer last_layer_ctx;
	// output:
	U64 out_n_cands;
	U64 out_parent_base;		 // parent index offset for tuples in this chunk
	U64 out_n_parents_chunk; // number of parents covered by this chunk
} Enum;

I32 enum_make(Enum* e, U64 batch_size);
void enum_free(Enum* e);

// run the upper layers of the backward search, on return, the last-layer
// frontier is staged inside e; call enum_emit_batch repeatedly to pull
// chunks of candidates until it returns 0
void enum_run(Enum* e, EnumOptions* opt);

// emit the next chunk of last-layer candidates, returns the number emitted
// (also written to e->out_n_cands)
U64 enum_emit_batch(Enum* e);
U64 enum_find_chunk_fit(U64* d_offsets, U64 cursor, U64 n_front, U64 total, U64 cap);

void enum_make_meta_host(EnumOpcodePool* pool, EnumMeta* out, U32* out_n);
void enum_make_opcode_pool(EnumOpcodePool* pool, U32 ext_mask);
void enum_make_imm_pool(EnumImmPool* pool, Program* prog);

#endif // OPT_ENUMERATE_CUH
