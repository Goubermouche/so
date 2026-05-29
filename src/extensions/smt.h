#ifndef EXT_SMT_H
#define EXT_SMT_H

#include "smt/smt.h"

inline B32 ext_smt(Z3_context ctx, SMT_State* s, SMT_Decode* d) {
	switch(d->op) {
		// rv32i
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
		// rv64i
		case InstructionOpcode_Addiw: SMT_WR(smt_sext_w(ctx, Z3_mk_bvadd(ctx, SMT_A, d->imm)));
		case InstructionOpcode_Addw:  SMT_WR(smt_sext_w(ctx, Z3_mk_bvadd(ctx, SMT_A, SMT_B)));
		case InstructionOpcode_Subw:  SMT_WR(smt_sext_w(ctx, Z3_mk_bvsub(ctx, SMT_A, SMT_B)));
		case InstructionOpcode_Slliw: SMT_WR(SMT_Sext(32, Z3_mk_bvshl(ctx, SMT_LO32(SMT_A), SMT_SH5_32(d->imm))));
		case InstructionOpcode_Srliw: SMT_WR(SMT_Sext(32, Z3_mk_bvlshr(ctx, SMT_LO32(SMT_A), SMT_SH5_32(d->imm))));
		case InstructionOpcode_Sraiw: SMT_WR(SMT_Sext(32, Z3_mk_bvashr(ctx, SMT_LO32(SMT_A), SMT_SH5_32(d->imm))));
		case InstructionOpcode_Sllw:  SMT_WR(SMT_Sext(32, Z3_mk_bvshl(ctx, SMT_LO32(SMT_A), SMT_SH5_32(SMT_B))));
		case InstructionOpcode_Srlw:  SMT_WR(SMT_Sext(32, Z3_mk_bvlshr(ctx, SMT_LO32(SMT_A), SMT_SH5_32(SMT_B))));
		case InstructionOpcode_Sraw:  SMT_WR(SMT_Sext(32, Z3_mk_bvashr(ctx, SMT_LO32(SMT_A), SMT_SH5_32(SMT_B))));
		// rv32m
		case InstructionOpcode_Mul:    SMT_WR(Z3_mk_bvmul(ctx, SMT_A, SMT_B));
		case InstructionOpcode_Mulh:   SMT_WR(SMT_Extract(127, 64, Z3_mk_bvmul(ctx, SMT_Sext(64, SMT_A), SMT_Sext(64, SMT_B))));
		case InstructionOpcode_Mulhsu: SMT_WR(SMT_Extract(127, 64, Z3_mk_bvmul(ctx, SMT_Sext(64, SMT_A), SMT_Zext(64, SMT_B))));
		case InstructionOpcode_Mulhu:  SMT_WR(SMT_Extract(127, 64, Z3_mk_bvmul(ctx, SMT_Zext(64, SMT_A), SMT_Zext(64, SMT_B))));
		case InstructionOpcode_Div: {
			Z3_ast minus_one = smt_bv64(ctx, (U64)-1);
			Z3_ast int_min = smt_bv64(ctx, 0x8000000000000000ULL);
			Z3_ast is_zero = SMT_Eq(SMT_B, smt_bv64(ctx, 0));
			Z3_ast is_ovf = SMT_OvfSigned(SMT_A, SMT_B, int_min, minus_one);
			Z3_ast inner = SMT_Ite(is_ovf, SMT_A, Z3_mk_bvsdiv(ctx, SMT_A, SMT_B));
			SMT_WR(SMT_Ite(is_zero, minus_one, inner));
		}
		case InstructionOpcode_Divu: {
			Z3_ast is_zero = SMT_Eq(SMT_B, smt_bv64(ctx, 0));
			SMT_WR(SMT_Ite(is_zero, smt_bv64(ctx, (U64)-1), Z3_mk_bvudiv(ctx, SMT_A, SMT_B)));
		}
		case InstructionOpcode_Rem: {
			Z3_ast zero = smt_bv64(ctx, 0);
			Z3_ast minus_one = smt_bv64(ctx, (U64)-1);
			Z3_ast int_min = smt_bv64(ctx, 0x8000000000000000ULL);
			Z3_ast is_zero = SMT_Eq(SMT_B, zero);
			Z3_ast is_ovf = SMT_OvfSigned(SMT_A, SMT_B, int_min, minus_one);
			Z3_ast inner = SMT_Ite(is_ovf, zero, Z3_mk_bvsrem(ctx, SMT_A, SMT_B));
			SMT_WR(SMT_Ite(is_zero, SMT_A, inner));
		}
		case InstructionOpcode_Remu: {
			Z3_ast is_zero = SMT_Eq(SMT_B, smt_bv64(ctx, 0));
			SMT_WR(SMT_Ite(is_zero, SMT_A, Z3_mk_bvurem(ctx, SMT_A, SMT_B)));
		}
		// rv64m
		case InstructionOpcode_Mulw: SMT_WR(SMT_Sext(32, Z3_mk_bvmul(ctx, SMT_LO32(SMT_A), SMT_LO32(SMT_B))));
		case InstructionOpcode_Divw: {
			Z3_ast a = SMT_LO32(SMT_A);
			Z3_ast b = SMT_LO32(SMT_B);
			Z3_ast all_ones = smt_bv32(ctx, 0xFFFFFFFF);
			Z3_ast int_min = smt_bv32(ctx, 0x80000000);
			Z3_ast is_zero = SMT_Eq(b, smt_bv32(ctx, 0));
			Z3_ast is_ovf = SMT_OvfSigned(a, b, int_min, all_ones);
			Z3_ast inner = SMT_Ite(is_ovf, a, Z3_mk_bvsdiv(ctx, a, b));
			SMT_WR(SMT_Sext(32, SMT_Ite(is_zero, all_ones, inner)));
		}
		case InstructionOpcode_Divuw: {
			Z3_ast a = SMT_LO32(SMT_A);
			Z3_ast b = SMT_LO32(SMT_B);
			Z3_ast is_zero = SMT_Eq(b, smt_bv32(ctx, 0));
			SMT_WR(SMT_Sext(32, SMT_Ite(is_zero, smt_bv32(ctx, 0xFFFFFFFF), Z3_mk_bvudiv(ctx, a, b))));
		}
		case InstructionOpcode_Remw: {
			Z3_ast a = SMT_LO32(SMT_A);
			Z3_ast b = SMT_LO32(SMT_B);
			Z3_ast all_ones = smt_bv32(ctx, 0xFFFFFFFF);
			Z3_ast int_min = smt_bv32(ctx, 0x80000000);
			Z3_ast is_zero = SMT_Eq(b, smt_bv32(ctx, 0));
			Z3_ast is_ovf = SMT_OvfSigned(a, b, int_min, all_ones);
			Z3_ast inner = SMT_Ite(is_ovf, smt_bv32(ctx, 0), Z3_mk_bvsrem(ctx, a, b));
			SMT_WR(SMT_Sext(32, SMT_Ite(is_zero, a, inner)));
		}
		case InstructionOpcode_Remuw: {
			Z3_ast a = SMT_LO32(SMT_A);
			Z3_ast b = SMT_LO32(SMT_B);
			Z3_ast is_zero = SMT_Eq(b, smt_bv32(ctx, 0));
			SMT_WR(SMT_Sext(32, SMT_Ite(is_zero, a, Z3_mk_bvurem(ctx, a, b))));
		}
	}
	return false;
}

#endif // EXT_SMT_H
