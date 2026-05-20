#ifndef EXT_RV64I_SMT_CUH
#define EXT_RV64I_SMT_CUH

#include "smt/smt.h"

namespace sup::smt {
inline b32 ext_rv64i_smt(z3::context& ctx, state& s, const decode& d) {
	switch(d.op) {
		case InstructionOpcode_Addiw: WR(sext_w(ctx, A + d.imm));
		case InstructionOpcode_Addw:  WR(sext_w(ctx, A + B));
		case InstructionOpcode_Subw:  WR(sext_w(ctx, A - B));
		case InstructionOpcode_Slliw: WR(SEXT(32, z3::shl(LO32(A), SH5_32(d.imm))));
		case InstructionOpcode_Srliw: WR(SEXT(32, z3::lshr(LO32(A), SH5_32(d.imm))));
		case InstructionOpcode_Sraiw: WR(SEXT(32, z3::ashr(LO32(A), SH5_32(d.imm))));
		case InstructionOpcode_Sllw:  WR(SEXT(32, z3::shl(LO32(A), SH5_32(B))));
		case InstructionOpcode_Srlw:  WR(SEXT(32, z3::lshr(LO32(A), SH5_32(B))));
		case InstructionOpcode_Sraw:  WR(SEXT(32, z3::ashr(LO32(A), SH5_32(B))));
	}
	return false;
}
} // namespace sup::smt

#endif // EXT_RV64I_SMT_CUH
