#ifndef EXT_RV32M_SMT_CUH
#define EXT_RV32M_SMT_CUH

#include "smt/smt.h"

inline b32 ext_rv32m_smt(z3::context& ctx, SMT_State& s, const SMT_Decode& d) {
	switch(d.op) {
		case InstructionOpcode_Mul:    WR(A * B);
		case InstructionOpcode_Mulh:   WR(EXTRACT(127, 64, SEXT(64, A) * SEXT(64, B)));
		case InstructionOpcode_Mulhsu: WR(EXTRACT(127, 64, SEXT(64, A) * ZEXT(64, B)));
		case InstructionOpcode_Mulhu:  WR(EXTRACT(127, 64, ZEXT(64, A) * ZEXT(64, B)));
		case InstructionOpcode_Div: {
			z3::expr minus_one = smt_bv64(ctx, (u64)-1);
			z3::expr int_min = smt_bv64(ctx, 0x8000000000000000ULL);
			z3::expr is_zero = EQUIVALENT(B, smt_bv64(ctx, 0));
			z3::expr is_ovf = OVF_SIGNED(A, B, int_min, minus_one);
			z3::expr inner = ITE(is_ovf, A, A / B);
			WR(ITE(is_zero, minus_one, inner));
		}
		case InstructionOpcode_Divu: {
			z3::expr is_zero = EQUIVALENT(B, smt_bv64(ctx, 0));
			WR(ITE(is_zero, smt_bv64(ctx, (u64)-1), z3::udiv(A, B)));
		}
		case InstructionOpcode_Rem: {
			z3::expr zero = smt_bv64(ctx, 0);
			z3::expr minus_one = smt_bv64(ctx, (u64)-1);
			z3::expr int_min = smt_bv64(ctx, 0x8000000000000000ULL);
			z3::expr is_zero = EQUIVALENT(B, zero);
			z3::expr is_ovf = OVF_SIGNED(A, B, int_min, minus_one);
			z3::expr inner = ITE(is_ovf, zero, z3::srem(A, B));
			WR(ITE(is_zero, A, inner));
		}
		case InstructionOpcode_Remu: {
			z3::expr is_zero = EQUIVALENT(B, smt_bv64(ctx, 0));
			WR(ITE(is_zero, A, z3::urem(A, B)));
		}
	}
	return false;
}

#endif // EXT_RV32M_SMT_CUH
