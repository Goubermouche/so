#ifndef SMT_SMT_H
#define SMT_SMT_H

#include "cpu/program.h"
#include "smt/state.h"

#define SMT_TIMEOUT_MS 10000

typedef enum smt_result {
	SMT_EQUIVALENT,
	SMT_COUNTEREXAMPLE,
	SMT_TIMEOUT,
	SMT_ERROR,
} smt_result;

typedef struct smt_verify_report {
	smt_result kind;
	cpu_state counterexample;
	f64 solve_ms;
	const char* error;
} smt_verify_report;

smt_state smt_run(Z3_context ctx, const smt_state* in, const cpu_program* prog);
smt_verify_report smt_eq(const cpu_program* a, const cpu_program* b, u64 live_outs);

#endif // #ifndef SMT_SMT_H
