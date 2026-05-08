#ifndef EXT_RV64M_SMT_CUH
#define EXT_RV64M_SMT_CUH

#include "int/instruction.cuh"
#include "ext/rv32i/smt.cuh"
#include <z3++.h>

namespace sup {
	inline bool ext_rv64m_smt(z3::context& ctx, smt_state& regs, u32 op, u32 d, u32 s1, u32 s2, const z3::expr& /*imm*/) {
		using namespace ext_smt;
		switch(op) {
			case OP_MULW: {
				z3::expr a = regs[s1].extract(31, 0);
				z3::expr b = regs[s2].extract(31, 0);
				wr(regs, d, z3::sext(a * b, 32));
				return true;
			}
			case OP_DIVW: {
				z3::expr a = regs[s1].extract(31, 0);
				z3::expr b = regs[s2].extract(31, 0);
				z3::expr is_zero = (b == ctx.bv_val((u64)0, 32));
				z3::expr is_ovf  = (a == ctx.bv_val((u64)0x80000000, 32)) && (b == ctx.bv_val((u64)0xFFFFFFFF, 32));
				z3::expr res = z3::ite(is_zero, ctx.bv_val((u64)0xFFFFFFFF, 32), z3::ite(is_ovf,  a, a / b));
				wr(regs, d, z3::sext(res, 32));
				return true;
			}
			case OP_DIVUW: {
				z3::expr a = regs[s1].extract(31, 0);
				z3::expr b = regs[s2].extract(31, 0);
				z3::expr is_zero = (b == ctx.bv_val((u64)0, 32));
				z3::expr res = z3::ite(is_zero, ctx.bv_val((u64)0xFFFFFFFF, 32), z3::udiv(a, b));
				wr(regs, d, z3::sext(res, 32));
				return true;
			}
			case OP_REMW: {
				z3::expr a = regs[s1].extract(31, 0);
				z3::expr b = regs[s2].extract(31, 0);
				z3::expr is_zero = (b == ctx.bv_val((u64)0, 32));
				z3::expr is_ovf  = (a == ctx.bv_val((u64)0x80000000, 32)) && (b == ctx.bv_val((u64)0xFFFFFFFF, 32));
				z3::expr res = z3::ite(is_zero, a, z3::ite(is_ovf,  ctx.bv_val((u64)0, 32), z3::srem(a, b)));
				wr(regs, d, z3::sext(res, 32));
				return true;
			}
			case OP_REMUW: {
				z3::expr a = regs[s1].extract(31, 0);
				z3::expr b = regs[s2].extract(31, 0);
				z3::expr is_zero = (b == ctx.bv_val((u64)0, 32));
				z3::expr res = z3::ite(is_zero, a, z3::urem(a, b));
				wr(regs, d, z3::sext(res, 32));
				return true;
			}
		}
		return false;
	}
} // namespace sup

#endif // #ifndef EXT_RV64M_SMT_CUH

