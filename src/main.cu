#include "opt/optimize.h"

so::i32 main() {
	if(so::device_init()) {
		return 1;
	}

	so::print("\n");

	so::optimize(
		"mov rbx, rax\n"
		"shl rbx, 2\n"
		"add rbx, rax\n"
	);

	return 0;
}

