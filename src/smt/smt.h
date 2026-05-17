#ifndef SMT_SMT_H
#define SMT_SMT_H

#include "cpu/program.h"
#include "smt/state.h"

#define SMT_TIMEOUT_MS 10000

typedef enum smt_result_kind {
	SMT_EQUIVALENT,
	SMT_COUNTEREXAMPLE,
	SMT_TIMEOUT,
	SMT_ERROR,
} smt_result_kind;

typedef struct smt_result {
	smt_result_kind kind;
	cpu_state counterexample;
	const c8* error;
} smt_result;

smt_state smt_run(Z3_context ctx, const smt_state* in, const cpu_program* p);
smt_result smt_eq(const cpu_program* a, const cpu_program* b, u64 live_outs);

#endif // #ifndef SMT_SMT_H
