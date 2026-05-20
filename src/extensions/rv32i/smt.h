#ifndef EXT_RV32I_SMT_CUH
#define EXT_RV32I_SMT_CUH

#include "smt/smt.h"

namespace sup::smt {
inline b32 ext_rv32i_smt(z3::context& ctx, state& s, const decode& d) {
	switch(d.op) {
		case InstructionOpcode_Add:   WR(A + B);
		case InstructionOpcode_Sub:   WR(A - B);
		case InstructionOpcode_Xor:   WR(A ^ B);
		case InstructionOpcode_Or:    WR(A | B);
		case InstructionOpcode_And:   WR(A & B);
		case InstructionOpcode_Sll:   WR(z3::shl(A, low6(ctx, B)));
		case InstructionOpcode_Srl:   WR(z3::lshr(A, low6(ctx, B)));
		case InstructionOpcode_Sra:   WR(z3::ashr(A, low6(ctx, B)));
		case InstructionOpcode_Slt:   WR(ite_bool_to_bv64(ctx, z3::slt(A, B)));
		case InstructionOpcode_Sltu:  WR(ite_bool_to_bv64(ctx, z3::ult(A, B)));
		case InstructionOpcode_Addi:  WR(A + d.imm);
		case InstructionOpcode_Xori:  WR(A ^ d.imm);
		case InstructionOpcode_Ori:   WR(A | d.imm);
		case InstructionOpcode_Andi:  WR(A & d.imm);
		case InstructionOpcode_Slli:  WR(z3::shl(A, low6(ctx, d.imm)));
		case InstructionOpcode_Srli:  WR(z3::lshr(A, low6(ctx, d.imm)));
		case InstructionOpcode_Srai:  WR(z3::ashr(A, low6(ctx, d.imm)));
		case InstructionOpcode_Slti:  WR(ite_bool_to_bv64(ctx, z3::slt(A, d.imm)));
		case InstructionOpcode_Sltiu: WR(ite_bool_to_bv64(ctx, z3::ult(A, d.imm)));
		case InstructionOpcode_Lui:   WR(sext_w(ctx, z3::shl(d.imm, bv64(ctx, 12))));
	}
	return false;
}
} // namespace sup::smt

#endif // EXT_RV32I_SMT_CUH
