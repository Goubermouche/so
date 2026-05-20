#ifndef EXT_RV64M_SMT_CUH
#define EXT_RV64M_SMT_CUH

#include "smt/smt.h"

namespace sup::smt {
inline b32 ext_rv64m_smt(z3::context& ctx, state& s, const decode& d) {
	switch(d.op) {
		case InstructionOpcode_Mulw: WR(SEXT(32, LO32(A) * LO32(B)));
		case InstructionOpcode_Divw: {
			z3::expr a = LO32(A);
			z3::expr b = LO32(B);
			z3::expr zero = bv32(ctx, 0);
			z3::expr all_ones = bv32(ctx, 0xFFFFFFFF);
			z3::expr int_min = bv32(ctx, 0x80000000);
			z3::expr is_zero = EQUIVALENT(b, zero);
			z3::expr is_ovf = OVF_SIGNED(a, b, int_min, all_ones);
			z3::expr inner = ITE(is_ovf, a, a / b);
			WR(SEXT(32, ITE(is_zero, all_ones, inner)));
		}
		case InstructionOpcode_Divuw: {
			z3::expr a = LO32(A);
			z3::expr b = LO32(B);
			z3::expr is_zero = EQUIVALENT(b, bv32(ctx, 0));
			WR(SEXT(32, ITE(is_zero, bv32(ctx, 0xFFFFFFFF), z3::udiv(a, b))));
		}
		case InstructionOpcode_Remw: {
			z3::expr a = LO32(A);
			z3::expr b = LO32(B);
			z3::expr zero = bv32(ctx, 0);
			z3::expr all_ones = bv32(ctx, 0xFFFFFFFF);
			z3::expr int_min = bv32(ctx, 0x80000000);
			z3::expr is_zero = EQUIVALENT(b, zero);
			z3::expr is_ovf = OVF_SIGNED(a, b, int_min, all_ones);
			z3::expr inner = ITE(is_ovf, zero, z3::srem(a, b));
			WR(SEXT(32, ITE(is_zero, a, inner)));
		}
		case InstructionOpcode_Remuw: {
			z3::expr a = LO32(A);
			z3::expr b = LO32(B);
			z3::expr is_zero = EQUIVALENT(b, bv32(ctx, 0));
			WR(SEXT(32, ITE(is_zero, a, z3::urem(a, b))));
		}
	}
	return false;
}
} // namespace sup::smt

#endif // EXT_RV64M_SMT_CUH
