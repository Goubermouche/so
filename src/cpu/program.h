#ifndef CPU_PROGRAM_H
#define CPU_PROGRAM_H

#include "cpu/instruction.cuh"

namespace sup {
struct program : slice<inst> {
	program() : slice<inst>() {}
	program(inst* ptr, u64 size) : slice<inst>(ptr, size) {}
	static program parse(arena& a, string source);

	string to_string(arena& a) const;
	u64 get_live_out() const;
};
} // namespace sup

#endif // #ifndef CPU_PROGRAM_H
