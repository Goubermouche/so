#ifndef EXT_RV32I_SMT_CUH
#define EXT_RV32I_SMT_CUH

#include "int/instruction.cuh"
#include <z3++.h>

namespace sup {
	using smt_state = std::array<z3::expr, 32>;

	namespace ext_smt {
		inline z3::expr low6(z3::context& ctx, const z3::expr& v) {
			return v & ctx.bv_val((u64)0x3F, 64);
		}

		inline z3::expr sext_w(z3::context& /*ctx*/, const z3::expr& v64) {
			return z3::sext(v64.extract(31, 0), 32);
		}

		inline void wr(smt_state& regs, u32 d, const z3::expr& v) {
			if(d == 0) {
				return;
			}

			regs[d] = v;
		}
	} // namespace ext_smt

	inline bool ext_rv32i_smt(z3::context& ctx, smt_state& regs, u32 op, u32 d, u32 s1, u32 s2, const z3::expr& imm) {
		using namespace ext_smt;

		switch(op) {
			case OP_ADD:   wr(regs, d, regs[s1] + regs[s2]); return true;
			case OP_SUB:   wr(regs, d, regs[s1] - regs[s2]); return true;
			case OP_SLL:   wr(regs, d, z3::shl( regs[s1], low6(ctx, regs[s2]))); return true;
			case OP_SLT:   wr(regs, d, z3::ite(z3::slt(regs[s1], regs[s2]), ctx.bv_val((u64)1, 64), ctx.bv_val((u64)0, 64))); return true;
			case OP_SLTU:  wr(regs, d, z3::ite(z3::ult(regs[s1], regs[s2]), ctx.bv_val((u64)1, 64), ctx.bv_val((u64)0, 64))); return true;
			case OP_XOR:   wr(regs, d, regs[s1] ^ regs[s2]); return true;
			case OP_SRL:   wr(regs, d, z3::lshr(regs[s1], low6(ctx, regs[s2]))); return true;
			case OP_SRA:   wr(regs, d, z3::ashr(regs[s1], low6(ctx, regs[s2]))); return true;
			case OP_OR:    wr(regs, d, regs[s1] | regs[s2]); return true;
			case OP_AND:   wr(regs, d, regs[s1] & regs[s2]); return true;
			case OP_ADDI:  wr(regs, d, regs[s1] + imm); return true;
			case OP_SLTI:  wr(regs, d, z3::ite(z3::slt(regs[s1], imm), ctx.bv_val((u64)1, 64), ctx.bv_val((u64)0, 64))); return true;
			case OP_SLTIU: wr(regs, d, z3::ite(z3::ult(regs[s1], imm), ctx.bv_val((u64)1, 64), ctx.bv_val((u64)0, 64))); return true;
			case OP_XORI:  wr(regs, d, regs[s1] ^ imm); return true;
			case OP_ORI:   wr(regs, d, regs[s1] | imm); return true;
			case OP_ANDI:  wr(regs, d, regs[s1] & imm); return true;
			case OP_SLLI:  wr(regs, d, z3::shl( regs[s1], low6(ctx, imm))); return true;
			case OP_SRLI:  wr(regs, d, z3::lshr(regs[s1], low6(ctx, imm))); return true;
			case OP_SRAI:  wr(regs, d, z3::ashr(regs[s1], low6(ctx, imm))); return true;
			case OP_LUI: {
				z3::expr shifted = z3::shl(imm, ctx.bv_val((u64)12, 64));
				wr(regs, d, sext_w(ctx, shifted));
				return true;
			}
		}

		return false;
	}
} // namespace sup

#endif // #ifndef EXT_RV32I_SMT_CUH

