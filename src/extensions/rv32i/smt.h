#ifndef EXT_RV32I_SMT_CUH
#define EXT_RV32I_SMT_CUH

#include "smt/smt.h"

inline B32 ext_rv32i_smt(Z3_context ctx, SMT_State* s, SMT_Decode* d) {
	switch(d->op) {
		case InstructionOpcode_Add:   SMT_WR(Z3_mk_bvadd(ctx, SMT_A, SMT_B));
		case InstructionOpcode_Sub:   SMT_WR(Z3_mk_bvsub(ctx, SMT_A, SMT_B));
		case InstructionOpcode_Xor:   SMT_WR(Z3_mk_bvxor(ctx, SMT_A, SMT_B));
		case InstructionOpcode_Or:    SMT_WR(Z3_mk_bvor(ctx, SMT_A, SMT_B));
		case InstructionOpcode_And:   SMT_WR(Z3_mk_bvand(ctx, SMT_A, SMT_B));
		case InstructionOpcode_Sll:   SMT_WR(Z3_mk_bvshl(ctx, SMT_A, smt_low6(ctx, SMT_B)));
		case InstructionOpcode_Srl:   SMT_WR(Z3_mk_bvlshr(ctx, SMT_A, smt_low6(ctx, SMT_B)));
		case InstructionOpcode_Sra:   SMT_WR(Z3_mk_bvashr(ctx, SMT_A, smt_low6(ctx, SMT_B)));
		case InstructionOpcode_Slt:   SMT_WR(smt_ite_bool_to_bv64(ctx, Z3_mk_bvslt(ctx, SMT_A, SMT_B)));
		case InstructionOpcode_Sltu:  SMT_WR(smt_ite_bool_to_bv64(ctx, Z3_mk_bvult(ctx, SMT_A, SMT_B)));
		case InstructionOpcode_Addi:  SMT_WR(Z3_mk_bvadd(ctx, SMT_A, d->imm));
		case InstructionOpcode_Xori:  SMT_WR(Z3_mk_bvxor(ctx, SMT_A, d->imm));
		case InstructionOpcode_Ori:   SMT_WR(Z3_mk_bvor(ctx, SMT_A, d->imm));
		case InstructionOpcode_Andi:  SMT_WR(Z3_mk_bvand(ctx, SMT_A, d->imm));
		case InstructionOpcode_Slli:  SMT_WR(Z3_mk_bvshl(ctx, SMT_A, smt_low6(ctx, d->imm)));
		case InstructionOpcode_Srli:  SMT_WR(Z3_mk_bvlshr(ctx, SMT_A, smt_low6(ctx, d->imm)));
		case InstructionOpcode_Srai:  SMT_WR(Z3_mk_bvashr(ctx, SMT_A, smt_low6(ctx, d->imm)));
		case InstructionOpcode_Slti:  SMT_WR(smt_ite_bool_to_bv64(ctx, Z3_mk_bvslt(ctx, SMT_A, d->imm)));
		case InstructionOpcode_Sltiu: SMT_WR(smt_ite_bool_to_bv64(ctx, Z3_mk_bvult(ctx, SMT_A, d->imm)));
		case InstructionOpcode_Lui:   SMT_WR(smt_sext_w(ctx, Z3_mk_bvshl(ctx, d->imm, smt_bv64(ctx, 12))));
	}
	return false;
}
#endif // EXT_RV32I_SMT_CUH