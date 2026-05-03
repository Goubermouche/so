#ifndef SMT_H
#define SMT_H

#include "int/instruction.cuh"
#include "int/cpu.cuh"

namespace so {
	enum verify_result {
		VERIFY_EQUIVALENT,
		VERIFY_COUNTEREXAMPLE,
		VERIFY_TIMEOUT,
		VERIFY_ERROR,
	};

	struct verify_report {
		verify_result kind;
		cpu_state counterexample;
		f64 solve_ms;
		const char* error;
	};

	verify_report verify_equivalent(
		const inst* target,
		u32 target_len,
		const inst* rewrite,
		u32 rewrite_len,
		u64 live_outs,
		u32 timeout_ms = 10'000
	);
} // namespace so

#endif // #ifndef SMT_H

