#ifndef EXT_RV64I_SMT_CUH
#define EXT_RV64I_SMT_CUH

#include "smt/state.h"

namespace sup {
inline bool ext_rv64i_smt(Z3_context ctx, smt_state* s, u32 op, u32 d, u32 s1, u32 s2, Z3_ast imm) {
	switch(op) {
		case OP_ADDIW: WR(smt_sext_w(ctx, Z3_mk_bvadd(ctx, A, imm)));
		case OP_ADDW:  WR(smt_sext_w(ctx, Z3_mk_bvadd(ctx, A, B)));
		case OP_SUBW:  WR(smt_sext_w(ctx, Z3_mk_bvsub(ctx, A, B)));
		case OP_SLLIW: WR(SEXT(32, Z3_mk_bvshl(ctx, LO32(A), SH5_32(imm))));
		case OP_SRLIW: WR(SEXT(32, Z3_mk_bvlshr(ctx, LO32(A), SH5_32(imm))));
		case OP_SRAIW: WR(SEXT(32, Z3_mk_bvashr(ctx, LO32(A), SH5_32(imm))));
		case OP_SLLW:  WR(SEXT(32, Z3_mk_bvshl(ctx, LO32(A), SH5_32(B))));
		case OP_SRLW:  WR(SEXT(32, Z3_mk_bvlshr(ctx, LO32(A), SH5_32(B))));
		case OP_SRAW:  WR(SEXT(32, Z3_mk_bvashr(ctx, LO32(A), SH5_32(B))));
	}
	return false;
}
} // namespace sup

#endif // EXT_RV64I_SMT_CUH
