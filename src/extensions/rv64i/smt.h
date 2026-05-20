#ifndef EXT_RV64I_SMT_CUH
#define EXT_RV64I_SMT_CUH

#include "smt/smt.h"

namespace sup::smt {
inline b32 ext_rv64i_smt(z3::context& ctx, state& s, const decode& d) {
	switch(d.op) {
		case OP_ADDIW: WR(sext_w(ctx, A + d.imm));
		case OP_ADDW:  WR(sext_w(ctx, A + B));
		case OP_SUBW:  WR(sext_w(ctx, A - B));
		case OP_SLLIW: WR(SEXT(32, z3::shl(LO32(A), SH5_32(d.imm))));
		case OP_SRLIW: WR(SEXT(32, z3::lshr(LO32(A), SH5_32(d.imm))));
		case OP_SRAIW: WR(SEXT(32, z3::ashr(LO32(A), SH5_32(d.imm))));
		case OP_SLLW:  WR(SEXT(32, z3::shl(LO32(A), SH5_32(B))));
		case OP_SRLW:  WR(SEXT(32, z3::lshr(LO32(A), SH5_32(B))));
		case OP_SRAW:  WR(SEXT(32, z3::ashr(LO32(A), SH5_32(B))));
	}
	return false;
}
} // namespace sup::smt

#endif // EXT_RV64I_SMT_CUH
