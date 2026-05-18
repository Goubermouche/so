#ifndef EXT_RV32I_SMT_CUH
#define EXT_RV32I_SMT_CUH

#include "smt/state.h"

namespace sup {
inline bool ext_rv32i_smt(Z3_context ctx, smt_state* s, u32 op, u32 d, u32 s1, u32 s2, Z3_ast imm) {
	switch(op) {
		case OP_ADD:   WR(Z3_mk_bvadd(ctx, A, B));
		case OP_SUB:   WR(Z3_mk_bvsub(ctx, A, B));
		case OP_XOR:   WR(Z3_mk_bvxor(ctx, A, B));
		case OP_OR:    WR(Z3_mk_bvor(ctx, A, B));
		case OP_AND:   WR(Z3_mk_bvand(ctx, A, B));
		case OP_SLL:   WR(Z3_mk_bvshl(ctx, A, smt_low6(ctx, B)));
		case OP_SRL:   WR(Z3_mk_bvlshr(ctx, A, smt_low6(ctx, B)));
		case OP_SRA:   WR(Z3_mk_bvashr(ctx, A, smt_low6(ctx, B)));
		case OP_SLT:   WR(smt_ite_bool_to_bv64(ctx, Z3_mk_bvslt(ctx, A, B)));
		case OP_SLTU:  WR(smt_ite_bool_to_bv64(ctx, Z3_mk_bvult(ctx, A, B)));
		case OP_ADDI:  WR(Z3_mk_bvadd(ctx, A, imm));
		case OP_XORI:  WR(Z3_mk_bvxor(ctx, A, imm));
		case OP_ORI:   WR(Z3_mk_bvor(ctx, A, imm));
		case OP_ANDI:  WR(Z3_mk_bvand(ctx, A, imm));
		case OP_SLLI:  WR(Z3_mk_bvshl(ctx, A, smt_low6(ctx, imm)));
		case OP_SRLI:  WR(Z3_mk_bvlshr(ctx, A, smt_low6(ctx, imm)));
		case OP_SRAI:  WR(Z3_mk_bvashr(ctx, A, smt_low6(ctx, imm)));
		case OP_SLTI:  WR(smt_ite_bool_to_bv64(ctx, Z3_mk_bvslt(ctx, A, imm)));
		case OP_SLTIU: WR(smt_ite_bool_to_bv64(ctx, Z3_mk_bvult(ctx, A, imm)));
		case OP_LUI:   WR(smt_sext_w(ctx, Z3_mk_bvshl(ctx, imm, smt_bv64(ctx, 12))));
	}
	return false;
}
} // namespace sup

#endif // EXT_RV32I_SMT_CUH
