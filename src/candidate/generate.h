#ifndef GENERATE_H
#define GENERATE_H

#include "equivalence/instruction.cuh"

namespace so {
	bool is_valid_next(
		const std::vector<inst>& prog,
		const inst& next
	);

	void try_candidate(
		arr<inst>& current,
		u32 target_len,
		const arr<inst_opcode>& opcodes,
		const arr<u8>& regs,
		arr<inst>& out_flat,
		inst next
	);

	void emit_nullary(
		arr<inst>& current,
		u32 target_len,
		const arr<inst_opcode>& opcodes,
		const arr<u8>& regs,
		arr<inst>& out_flat,
		inst_tag tag
	);

	void emit_unary(
		arr<inst>& current,
		u32 target_len,
		const arr<inst_opcode>& opcodes,
		const arr<u8>& regs,
		arr<inst>& out_flat,
		inst_tag tag
	);

	void emit_binary_rr(
		arr<inst>& current,
		u32 target_len,
		const arr<inst_opcode>& opcodes,
		const arr<u8>& regs,
		arr<inst>& out_flat,
		inst_tag tag
	);

	void emit_binary_ri(
		arr<inst>& current,
		u32 target_len,
		const arr<inst_opcode>& opcodes,
		const arr<u8>& regs,
		arr<inst>& out_flat,
		inst_tag tag,
		const arr<u64>& immediates
	);

	void generate_candidates(
		arr<inst>& current,
		u32 target_len,
		const arr<inst_opcode>& opcodes,
		const arr<u8>& regs,
		arr<inst>& out_flat
	);
} // namespace so

#endif // #ifndef GENERATE_H
