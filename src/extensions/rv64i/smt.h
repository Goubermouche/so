#ifndef EXT_RV64I_SMT_CUH
#define EXT_RV64I_SMT_CUH

#include "smt/smt.h"

inline B32 ext_rv64i_smt(Z3_context ctx, SMT_State* s, SMT_Decode* d) {
	switch(d->op) {
		case InstructionOpcode_Addiw: SMT_WR(smt_sext_w(ctx, Z3_mk_bvadd(ctx, SMT_A, d->imm)));
		case InstructionOpcode_Addw:  SMT_WR(smt_sext_w(ctx, Z3_mk_bvadd(ctx, SMT_A, SMT_B)));
		case InstructionOpcode_Subw:  SMT_WR(smt_sext_w(ctx, Z3_mk_bvsub(ctx, SMT_A, SMT_B)));
		case InstructionOpcode_Slliw: SMT_WR(SMT_Sext(32, Z3_mk_bvshl(ctx, SMT_LO32(SMT_A), SMT_SH5_32(d->imm))));
		case InstructionOpcode_Srliw: SMT_WR(SMT_Sext(32, Z3_mk_bvlshr(ctx, SMT_LO32(SMT_A), SMT_SH5_32(d->imm))));
		case InstructionOpcode_Sraiw: SMT_WR(SMT_Sext(32, Z3_mk_bvashr(ctx, SMT_LO32(SMT_A), SMT_SH5_32(d->imm))));
		case InstructionOpcode_Sllw:  SMT_WR(SMT_Sext(32, Z3_mk_bvshl(ctx, SMT_LO32(SMT_A), SMT_SH5_32(SMT_B))));
		case InstructionOpcode_Srlw:  SMT_WR(SMT_Sext(32, Z3_mk_bvlshr(ctx, SMT_LO32(SMT_A), SMT_SH5_32(SMT_B))));
		case InstructionOpcode_Sraw:  SMT_WR(SMT_Sext(32, Z3_mk_bvashr(ctx, SMT_LO32(SMT_A), SMT_SH5_32(SMT_B))));
	}
	return false;
}
#endif // EXT_RV64I_SMT_CUH