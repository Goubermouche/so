#ifndef SMT_STATE_H
#define SMT_STATE_H

#include "int/instruction.cuh"
#include <z3.h>

typedef struct smt_state {
	Z3_ast r[32];
} smt_state;

using smt_state = std::array<Z3_ast, 32>;

Z3_ast smt_low6(Z3_context ctx, Z3_ast v);
Z3_ast smt_sext_w(Z3_context ctx, Z3_ast v64);
Z3_ast smt_bv64(Z3_context ctx, u64 v);
Z3_ast smt_ite_bool_to_bv64(Z3_context ctx, Z3_ast cond);
void smt_wr(Z3_context ctx, smt_state& regs, u32 d, Z3_ast v);

// release every slot of an smt_state
void smt_free_state(Z3_context ctx, smt_state& regs);

#endif // SMT_STATE_H
