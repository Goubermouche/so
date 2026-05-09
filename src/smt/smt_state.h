#ifndef SMT_STATE_H
#define SMT_STATE_H

#include "int/instruction.cuh"
#include <z3.h>

typedef struct smt_state {
	Z3_ast r[32];
} smt_state;

Z3_ast smt_low6(Z3_context ctx, Z3_ast v);
Z3_ast smt_sext_w(Z3_context ctx, Z3_ast v64);
Z3_ast smt_bv64(Z3_context ctx, u64 v);
Z3_ast smt_ite_bool_to_bv64(Z3_context ctx, Z3_ast cond);
Z3_ast smt_mk_bv64_const(Z3_context ctx, const char* name);

void smt_wr(Z3_context ctx, smt_state* state, u32 d, Z3_ast v);
void smt_pin_x0(Z3_context ctx, smt_state* state);

smt_state smt_make_input_state(Z3_context ctx);
void smt_free_state(Z3_context ctx, smt_state* state);
smt_state smt_clone_state(Z3_context ctx, const smt_state* src);

#endif // SMT_STATE_H
