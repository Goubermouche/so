#ifndef EXT_RV32I_SMT_CUH
#define EXT_RV32I_SMT_CUH

#include "smt/smt.h"

namespace sup::smt {
inline b32 ext_rv32i_smt(z3::context& ctx, state& s, const decode& d) {
	switch(d.op) {
		case OP_ADD:   WR(A + B);
		case OP_SUB:   WR(A - B);
		case OP_XOR:   WR(A ^ B);
		case OP_OR:    WR(A | B);
		case OP_AND:   WR(A & B);
		case OP_SLL:   WR(z3::shl(A, low6(ctx, B)));
		case OP_SRL:   WR(z3::lshr(A, low6(ctx, B)));
		case OP_SRA:   WR(z3::ashr(A, low6(ctx, B)));
		case OP_SLT:   WR(ite_bool_to_bv64(ctx, z3::slt(A, B)));
		case OP_SLTU:  WR(ite_bool_to_bv64(ctx, z3::ult(A, B)));
		case OP_ADDI:  WR(A + d.imm);
		case OP_XORI:  WR(A ^ d.imm);
		case OP_ORI:   WR(A | d.imm);
		case OP_ANDI:  WR(A & d.imm);
		case OP_SLLI:  WR(z3::shl(A, low6(ctx, d.imm)));
		case OP_SRLI:  WR(z3::lshr(A, low6(ctx, d.imm)));
		case OP_SRAI:  WR(z3::ashr(A, low6(ctx, d.imm)));
		case OP_SLTI:  WR(ite_bool_to_bv64(ctx, z3::slt(A, d.imm)));
		case OP_SLTIU: WR(ite_bool_to_bv64(ctx, z3::ult(A, d.imm)));
		case OP_LUI:   WR(sext_w(ctx, z3::shl(d.imm, bv64(ctx, 12))));
	}
	return false;
}
} // namespace sup::smt

#endif // EXT_RV32I_SMT_CUH
