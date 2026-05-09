#ifndef EXT_RV64I_SMT_CUH
#define EXT_RV64I_SMT_CUH

#include "smt/smt_state.h"

inline bool ext_rv64i_smt(Z3_context ctx, smt_state& regs, u32 op, u32 d, u32 s1, u32 s2,
													Z3_ast imm) {
	switch(op) {
	case OP_ADDIW: smt_wr(ctx, regs, d, smt_sext_w(ctx, Z3_mk_bvadd(ctx, regs[s1], imm))); return true;
	case OP_SLLIW: {
		Z3_ast lo32 = Z3_mk_extract(ctx, 31, 0, regs[s1]);
		Z3_ast cnt = Z3_mk_zero_ext(ctx, 27, Z3_mk_extract(ctx, 4, 0, imm));
		smt_wr(ctx, regs, d, Z3_mk_sign_ext(ctx, 32, Z3_mk_bvshl(ctx, lo32, cnt)));
		return true;
	}
	case OP_SRLIW: {
		Z3_ast lo32 = Z3_mk_extract(ctx, 31, 0, regs[s1]);
		Z3_ast cnt = Z3_mk_zero_ext(ctx, 27, Z3_mk_extract(ctx, 4, 0, imm));
		smt_wr(ctx, regs, d, Z3_mk_sign_ext(ctx, 32, Z3_mk_bvlshr(ctx, lo32, cnt)));
		return true;
	}
	case OP_SRAIW: {
		Z3_ast lo32 = Z3_mk_extract(ctx, 31, 0, regs[s1]);
		Z3_ast cnt = Z3_mk_zero_ext(ctx, 27, Z3_mk_extract(ctx, 4, 0, imm));
		smt_wr(ctx, regs, d, Z3_mk_sign_ext(ctx, 32, Z3_mk_bvashr(ctx, lo32, cnt)));
		return true;
	}
	case OP_ADDW:
		smt_wr(ctx, regs, d, smt_sext_w(ctx, Z3_mk_bvadd(ctx, regs[s1], regs[s2])));
		return true;
	case OP_SUBW:
		smt_wr(ctx, regs, d, smt_sext_w(ctx, Z3_mk_bvsub(ctx, regs[s1], regs[s2])));
		return true;
	case OP_SLLW: {
		Z3_ast lo32 = Z3_mk_extract(ctx, 31, 0, regs[s1]);
		Z3_ast cnt = Z3_mk_zero_ext(ctx, 27, Z3_mk_extract(ctx, 4, 0, regs[s2]));
		smt_wr(ctx, regs, d, Z3_mk_sign_ext(ctx, 32, Z3_mk_bvshl(ctx, lo32, cnt)));
		return true;
	}
	case OP_SRLW: {
		Z3_ast lo32 = Z3_mk_extract(ctx, 31, 0, regs[s1]);
		Z3_ast cnt = Z3_mk_zero_ext(ctx, 27, Z3_mk_extract(ctx, 4, 0, regs[s2]));
		smt_wr(ctx, regs, d, Z3_mk_sign_ext(ctx, 32, Z3_mk_bvlshr(ctx, lo32, cnt)));
		return true;
	}
	case OP_SRAW: {
		Z3_ast lo32 = Z3_mk_extract(ctx, 31, 0, regs[s1]);
		Z3_ast cnt = Z3_mk_zero_ext(ctx, 27, Z3_mk_extract(ctx, 4, 0, regs[s2]));
		smt_wr(ctx, regs, d, Z3_mk_sign_ext(ctx, 32, Z3_mk_bvashr(ctx, lo32, cnt)));
		return true;
	}
	}
	return false;
}

#endif // #ifndef EXT_RV64I_SMT_CUH
