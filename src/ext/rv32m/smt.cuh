#ifndef EXT_RV32M_SMT_CUH
#define EXT_RV32M_SMT_CUH

#include "int/instruction.cuh"
#include "ext/rv32i/smt.cuh"
#include <z3++.h>

namespace sup {
	inline bool ext_rv32m_smt(z3::context& ctx, smt_state& regs, u32 op, u32 d, u32 s1, u32 s2, const z3::expr& /*imm*/) {
		using namespace ext_smt;
		switch(op) {
			case OP_MUL: wr(regs, d, regs[s1] * regs[s2]); return true;
			case OP_MULH: {
				z3::expr a = z3::sext(regs[s1], 64);
				z3::expr b = z3::sext(regs[s2], 64);
				wr(regs, d, (a * b).extract(127, 64));
				return true;
			}
			case OP_MULHSU: {
				z3::expr a = z3::sext(regs[s1], 64);
				z3::expr b = z3::zext(regs[s2], 64);
				wr(regs, d, (a * b).extract(127, 64));
				return true;
			}
			case OP_MULHU: {
				z3::expr a = z3::zext(regs[s1], 64);
				z3::expr b = z3::zext(regs[s2], 64);
				wr(regs, d, (a * b).extract(127, 64));
				return true;
			}
			case OP_DIV: {
				z3::expr a = regs[s1];
				z3::expr b = regs[s2];
				z3::expr is_zero = (b == ctx.bv_val((u64)0, 64));
				z3::expr is_ovf  = (a == ctx.bv_val((u64)0x8000000000000000ULL, 64)) && (b == ctx.bv_val((u64)-1, 64));
				z3::expr q = z3::ite(is_zero, ctx.bv_val((u64)-1, 64), z3::ite(is_ovf,  a, a / b));
				wr(regs, d, q);
				return true;
			}
			case OP_DIVU: {
				z3::expr a = regs[s1];
				z3::expr b = regs[s2];
				z3::expr is_zero = (b == ctx.bv_val((u64)0, 64));
				wr(regs, d, z3::ite(is_zero, ctx.bv_val((u64)-1, 64), z3::udiv(a, b)));
				return true;
			}
			case OP_REM: {
				z3::expr a = regs[s1];
				z3::expr b = regs[s2];
				z3::expr is_zero = (b == ctx.bv_val((u64)0, 64));
				z3::expr is_ovf  = (a == ctx.bv_val((u64)0x8000000000000000ULL, 64)) && (b == ctx.bv_val((u64)-1, 64));
				z3::expr q = z3::ite(is_zero, a, z3::ite(is_ovf,  ctx.bv_val((u64)0, 64), z3::srem(a, b)));
				wr(regs, d, q);
				return true;
			}
			case OP_REMU: {
				z3::expr a = regs[s1];
				z3::expr b = regs[s2];
				z3::expr is_zero = (b == ctx.bv_val((u64)0, 64));
				wr(regs, d, z3::ite(is_zero, a, z3::urem(a, b)));
				return true;
			}
		}
		return false;
	}
} // namespace sup

#endif // #ifndef EXT_RV32M_SMT_CUH

