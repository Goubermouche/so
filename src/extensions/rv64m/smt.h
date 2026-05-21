#ifndef EXT_RV64M_SMT_CUH
#define EXT_RV64M_SMT_CUH

#include "smt/smt.h"

inline b32 ext_rv64m_smt(Z3_context ctx, SMT_State* s, const SMT_Decode* d) {
	switch(d->op) {
		case InstructionOpcode_Mulw: SMT_WR(SMT_Sext(32, Z3_mk_bvmul(ctx, SMT_LO32(SMT_A), SMT_LO32(SMT_B))));
		case InstructionOpcode_Divw: {
			Z3_ast a = SMT_LO32(SMT_A);
			Z3_ast b = SMT_LO32(SMT_B);
			Z3_ast zero = smt_bv32(ctx, 0);
			Z3_ast all_ones = smt_bv32(ctx, 0xFFFFFFFF);
			Z3_ast int_min = smt_bv32(ctx, 0x80000000);
			Z3_ast is_zero = SMT_Eq(b, zero);
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
			Z3_ast zero = smt_bv32(ctx, 0);
			Z3_ast all_ones = smt_bv32(ctx, 0xFFFFFFFF);
			Z3_ast int_min = smt_bv32(ctx, 0x80000000);
			Z3_ast is_zero = SMT_Eq(b, zero);
			Z3_ast is_ovf = SMT_OvfSigned(a, b, int_min, all_ones);
			Z3_ast inner = SMT_Ite(is_ovf, zero, Z3_mk_bvsrem(ctx, a, b));
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
#endif // EXT_RV64M_SMT_CUH