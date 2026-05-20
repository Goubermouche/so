#ifndef EXT_RV32M_SMT_CUH
#define EXT_RV32M_SMT_CUH

#include "smt/smt.h"

namespace sup::smt {
inline b32 ext_rv32m_smt(z3::context& ctx, state& s, const decode& d) {
	switch(d.op) {
		case OP_MUL:    WR(A * B);
		case OP_MULH:   WR(EXTRACT(127, 64, SEXT(64, A) * SEXT(64, B)));
		case OP_MULHSU: WR(EXTRACT(127, 64, SEXT(64, A) * ZEXT(64, B)));
		case OP_MULHU:  WR(EXTRACT(127, 64, ZEXT(64, A) * ZEXT(64, B)));
		case OP_DIV: {
			z3::expr minus_one = bv64(ctx, (u64)-1);
			z3::expr int_min = bv64(ctx, 0x8000000000000000ULL);
			z3::expr is_zero = EQUIVALENT(B, bv64(ctx, 0));
			z3::expr is_ovf = OVF_SIGNED(A, B, int_min, minus_one);
			z3::expr inner = ITE(is_ovf, A, A / B);
			WR(ITE(is_zero, minus_one, inner));
		}
		case OP_DIVU: {
			z3::expr is_zero = EQUIVALENT(B, bv64(ctx, 0));
			WR(ITE(is_zero, bv64(ctx, (u64)-1), z3::udiv(A, B)));
		}
		case OP_REM: {
			z3::expr zero = bv64(ctx, 0);
			z3::expr minus_one = bv64(ctx, (u64)-1);
			z3::expr int_min = bv64(ctx, 0x8000000000000000ULL);
			z3::expr is_zero = EQUIVALENT(B, zero);
			z3::expr is_ovf = OVF_SIGNED(A, B, int_min, minus_one);
			z3::expr inner = ITE(is_ovf, zero, z3::srem(A, B));
			WR(ITE(is_zero, A, inner));
		}
		case OP_REMU: {
			z3::expr is_zero = EQUIVALENT(B, bv64(ctx, 0));
			WR(ITE(is_zero, A, z3::urem(A, B)));
		}
	}
	return false;
}
} // namespace sup::smt

#endif // EXT_RV32M_SMT_CUH
