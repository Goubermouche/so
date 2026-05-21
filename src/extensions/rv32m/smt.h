#ifndef EXT_RV32M_SMT_CUH
#define EXT_RV32M_SMT_CUH

#include "smt/smt.h"

inline b32 ext_rv32m_smt(Z3_context ctx, SMT_State* s, const SMT_Decode* d) {
	switch(d->op) {
		case InstructionOpcode_Mul:    SMT_WR(Z3_mk_bvmul(ctx, SMT_A, SMT_B));
		case InstructionOpcode_Mulh:   SMT_WR(SMT_Extract(127, 64, Z3_mk_bvmul(ctx, SMT_Sext(64, SMT_A), SMT_Sext(64, SMT_B))));
		case InstructionOpcode_Mulhsu: SMT_WR(SMT_Extract(127, 64, Z3_mk_bvmul(ctx, SMT_Sext(64, SMT_A), SMT_Zext(64, SMT_B))));
		case InstructionOpcode_Mulhu:  SMT_WR(SMT_Extract(127, 64, Z3_mk_bvmul(ctx, SMT_Zext(64, SMT_A), SMT_Zext(64, SMT_B))));
		case InstructionOpcode_Div: {
			Z3_ast minus_one = smt_bv64(ctx, (u64)-1);
			Z3_ast int_min = smt_bv64(ctx, 0x8000000000000000ULL);
			Z3_ast is_zero = SMT_Eq(SMT_B, smt_bv64(ctx, 0));
			Z3_ast is_ovf = SMT_OvfSigned(SMT_A, SMT_B, int_min, minus_one);
			Z3_ast inner = SMT_Ite(is_ovf, SMT_A, Z3_mk_bvsdiv(ctx, SMT_A, SMT_B));
			SMT_WR(SMT_Ite(is_zero, minus_one, inner));
		}
		case InstructionOpcode_Divu: {
			Z3_ast is_zero = SMT_Eq(SMT_B, smt_bv64(ctx, 0));
			SMT_WR(SMT_Ite(is_zero, smt_bv64(ctx, (u64)-1), Z3_mk_bvudiv(ctx, SMT_A, SMT_B)));
		}
		case InstructionOpcode_Rem: {
			Z3_ast zero = smt_bv64(ctx, 0);
			Z3_ast minus_one = smt_bv64(ctx, (u64)-1);
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
	}
	return false;
}
#endif // EXT_RV32M_SMT_CUH