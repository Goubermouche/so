#ifndef INTERPRETER_H
#define INTERPRETER_H

#include "interpreter/instruction.h"

namespace so {
	void run_program(cpu_state* cpu, const inst* prog, u64 prog_size);
	u64 calculate_program_cost(const inst* prog, u64 prog_size);
}

#endif //INTERPRETER_H

