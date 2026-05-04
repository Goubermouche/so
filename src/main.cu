#include "opt/optimize.h"

sup::i32 main() {
	if(sup::device_init()) {
		return 1;
	}

	sup::print("\n");

	sup::optimize(
		"mov rbx, rax\n"
		"shl rbx, 2\n"
		"add rbx, rax\n"
	);

	return 0;
}

