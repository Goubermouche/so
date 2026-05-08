#include "opt/optimize.h"

sup::i32 main() {
	if(sup::device_init()) {
		return 1;
	}

	sup::config cfg;
	cfg.ext_mask = sup::EXT_RV32I | sup::EXT_RV32M;
	cfg.max_prog_len = 3;

	sup::optimize(
		"slli x11, x10, 2\n"
		"slli x12, x10, 3\n"
		"add  x10, x11, x12\n",
		cfg
	);

	return 0;
}
