#ifndef EXT_RV64I_SMT_CUH
#define EXT_RV64I_SMT_CUH

#include "int/instruction.cuh"
#include "ext/rv32i/smt.cuh"
#include <z3++.h>

namespace sup {
	inline bool ext_rv64i_smt(z3::context& ctx, smt_state& regs, u32 op, u32 d, u32 s1, u32 s2, const z3::expr& imm) {
		using namespace ext_smt;
		switch(op) {
			case OP_ADDIW: wr(regs, d, sext_w(ctx, regs[s1] + imm)); return true;
			case OP_SLLIW: {
				z3::expr lo32 = regs[s1].extract(31, 0);
				z3::expr cnt  = z3::zext(imm.extract(4, 0), 27);
				wr(regs, d, z3::sext(z3::shl(lo32, cnt), 32));
				return true;
			}
			case OP_SRLIW: {
				z3::expr lo32 = regs[s1].extract(31, 0);
				z3::expr cnt  = z3::zext(imm.extract(4, 0), 27);
				wr(regs, d, z3::sext(z3::lshr(lo32, cnt), 32));
				return true;
			}
			case OP_SRAIW: {
				z3::expr lo32 = regs[s1].extract(31, 0);
				z3::expr cnt  = z3::zext(imm.extract(4, 0), 27);
				wr(regs, d, z3::sext(z3::ashr(lo32, cnt), 32));
				return true;
			}
			case OP_ADDW: wr(regs, d, sext_w(ctx, regs[s1] + regs[s2])); return true;
			case OP_SUBW: wr(regs, d, sext_w(ctx, regs[s1] - regs[s2])); return true;
			case OP_SLLW: {
				z3::expr lo32 = regs[s1].extract(31, 0);
				z3::expr cnt  = z3::zext(regs[s2].extract(4, 0), 27);
				wr(regs, d, z3::sext(z3::shl(lo32, cnt), 32));
				return true;
			}
			case OP_SRLW: {
				z3::expr lo32 = regs[s1].extract(31, 0);
				z3::expr cnt  = z3::zext(regs[s2].extract(4, 0), 27);
				wr(regs, d, z3::sext(z3::lshr(lo32, cnt), 32));
				return true;
			}
			case OP_SRAW: {
				z3::expr lo32 = regs[s1].extract(31, 0);
				z3::expr cnt  = z3::zext(regs[s2].extract(4, 0), 27);
				wr(regs, d, z3::sext(z3::ashr(lo32, cnt), 32));
				return true;
			}
		}

		return false;
	}
} // namespace sup

#endif // #ifndef EXT_RV64I_SMT_CUH

