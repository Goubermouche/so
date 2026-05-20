#ifndef CPU_PROGRAM_H
#define CPU_PROGRAM_H

#include "extensions/database.cuh"

namespace sup {
struct program : slice<Instruction> {
	program() : slice<Instruction>() {}
	program(Instruction* ptr, u64 size) : slice<Instruction>(ptr, size) {}
	static program parse(arena& a, string source);

	string to_string(arena& a) const;
	u64 get_live_out() const;
	u64 get_live_in() const;
};
} // namespace sup

#endif // #ifndef CPU_PROGRAM_H
