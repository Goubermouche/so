#include "interpreter/cpu_state.h"
#include "interpreter/instruction.h"
#include "interpreter/interpreter.h"
#include "interpreter/program.h"

using namespace so::type;

i32 main() {
	so::str program_source =
		"mov ebx, eax\n"
		"mov ecx, eax\n"
		"neg ecx\n";

	so::program program = so::program::parse(program_source);
	so::print("{}", program.to_string());
	so::cpu_state cpu = {0};

	so::run_program(&cpu, program.instructions.data(), program.instructions.size());
	return 0;
}
