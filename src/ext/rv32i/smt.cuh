#ifndef EXT_RV32I_SMT_CUH
#define EXT_RV32I_SMT_CUH

#include "smt/smt_state.h"



inline bool ext_rv32i_smt(Z3_context ctx, smt_state& regs, u32 op, u32 d, u32 s1, u32 s2,
													Z3_ast imm) {
	switch(op) {
	case OP_ADD: smt_wr(ctx, regs, d, Z3_mk_bvadd(ctx, regs[s1], regs[s2])); return true;
	case OP_SUB: smt_wr(ctx, regs, d, Z3_mk_bvsub(ctx, regs[s1], regs[s2])); return true;
	case OP_SLL:
		smt_wr(ctx, regs, d, Z3_mk_bvshl(ctx, regs[s1], smt_low6(ctx, regs[s2])));
		return true;
	case OP_SLT:
		smt_wr(ctx, regs, d, smt_ite_bool_to_bv64(ctx, Z3_mk_bvslt(ctx, regs[s1], regs[s2])));
		return true;
	case OP_SLTU:
		smt_wr(ctx, regs, d, smt_ite_bool_to_bv64(ctx, Z3_mk_bvult(ctx, regs[s1], regs[s2])));
		return true;
	case OP_XOR: smt_wr(ctx, regs, d, Z3_mk_bvxor(ctx, regs[s1], regs[s2])); return true;
	case OP_SRL:
		smt_wr(ctx, regs, d, Z3_mk_bvlshr(ctx, regs[s1], smt_low6(ctx, regs[s2])));
		return true;
	case OP_SRA:
		smt_wr(ctx, regs, d, Z3_mk_bvashr(ctx, regs[s1], smt_low6(ctx, regs[s2])));
		return true;
	case OP_OR: smt_wr(ctx, regs, d, Z3_mk_bvor(ctx, regs[s1], regs[s2])); return true;
	case OP_AND: smt_wr(ctx, regs, d, Z3_mk_bvand(ctx, regs[s1], regs[s2])); return true;
	case OP_ADDI: smt_wr(ctx, regs, d, Z3_mk_bvadd(ctx, regs[s1], imm)); return true;
	case OP_SLTI:
		smt_wr(ctx, regs, d, smt_ite_bool_to_bv64(ctx, Z3_mk_bvslt(ctx, regs[s1], imm)));
		return true;
	case OP_SLTIU:
		smt_wr(ctx, regs, d, smt_ite_bool_to_bv64(ctx, Z3_mk_bvult(ctx, regs[s1], imm)));
		return true;
	case OP_XORI: smt_wr(ctx, regs, d, Z3_mk_bvxor(ctx, regs[s1], imm)); return true;
	case OP_ORI: smt_wr(ctx, regs, d, Z3_mk_bvor(ctx, regs[s1], imm)); return true;
	case OP_ANDI: smt_wr(ctx, regs, d, Z3_mk_bvand(ctx, regs[s1], imm)); return true;
	case OP_SLLI: smt_wr(ctx, regs, d, Z3_mk_bvshl(ctx, regs[s1], smt_low6(ctx, imm))); return true;
	case OP_SRLI: smt_wr(ctx, regs, d, Z3_mk_bvlshr(ctx, regs[s1], smt_low6(ctx, imm))); return true;
	case OP_SRAI: smt_wr(ctx, regs, d, Z3_mk_bvashr(ctx, regs[s1], smt_low6(ctx, imm))); return true;
	case OP_LUI: {
		Z3_ast shifted = Z3_mk_bvshl(ctx, imm, smt_bv64(ctx, 12));
		smt_wr(ctx, regs, d, smt_sext_w(ctx, shifted));
		return true;
	}
	}
	return false;
}

#endif // #ifndef EXT_RV32I_SMT_CUH
