#include "assembler/parser.h"

using namespace so::type;

i32 main() {
	// in: eax
	// out: eax
	so::str snippet =
		"mov ebx, eax\n"
		"sub ebx, 1\n"
		"not ebx\n"
		"and eax, ebx\n"
	;

	// target:
	// in: eax
	// out: eax
	//  mov ebx, eax
	//  neg ebx
	//  and eax, ebx

	// parse
	so::arr<so::inst> parsed = so::parser::parse(snippet);
	so::print("parsed {} instructions\n", parsed.size());
	for(const so::inst& inst : parsed) {
		so::print("{}\n", inst.to_string());
	}

	return 0;
}
