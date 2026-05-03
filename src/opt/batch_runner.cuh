#ifndef BATCH_RUNNER_CUH
#define BATCH_RUNNER_CUH

#include "int/instruction.cuh"

namespace so {
	SO_HD void run_program_lane(u64 regs[16], const inst* prog, u32 prog_len) {
		for(u32 i = 0; i < prog_len; ++i) {
			const inst& in = prog[i];

			switch(in.op) {
				case OP_NOP: break;
				case OP_MOV_R64_R64:  regs[in.operands[0].reg] = regs[in.operands[1].reg]; break;
				case OP_MOV_R64_I64:  regs[in.operands[0].reg] = in.operands[1].i; break;
				case OP_ADD_R64_R64:  regs[in.operands[0].reg] += regs[in.operands[1].reg]; break;
				case OP_ADD_R64_I64:  regs[in.operands[0].reg] += in.operands[1].i; break;
				case OP_SUB_R64_R64:  regs[in.operands[0].reg] -= regs[in.operands[1].reg]; break;
				case OP_SUB_R64_I64:  regs[in.operands[0].reg] -= in.operands[1].i; break;
				case OP_NEG_R64:      regs[in.operands[0].reg] = (u64)(-(i64)regs[in.operands[0].reg]); break;
				case OP_IMUL_R64_R64: regs[in.operands[0].reg] *= regs[in.operands[1].reg]; break;
				case OP_IMUL_R64_I64: regs[in.operands[0].reg] *= in.operands[1].i; break;
				case OP_AND_R64_R64:  regs[in.operands[0].reg] &= regs[in.operands[1].reg]; break;
				case OP_AND_R64_I64:  regs[in.operands[0].reg] &= in.operands[1].i; break;
				case OP_OR_R64_R64:   regs[in.operands[0].reg] |= regs[in.operands[1].reg]; break;
				case OP_OR_R64_I64:   regs[in.operands[0].reg] |= in.operands[1].i; break;
				case OP_XOR_R64_R64:  regs[in.operands[0].reg] ^= regs[in.operands[1].reg]; break;
				case OP_XOR_R64_I64:  regs[in.operands[0].reg] ^= in.operands[1].i; break;
				case OP_NOT_R64:      regs[in.operands[0].reg] = ~regs[in.operands[0].reg]; break;
				case OP_SHL_R64_I64: {
					const u32 cnt = (u32)(in.operands[1].i & 0x3F);
					regs[in.operands[0].reg] <<= cnt;
					break;
				}
				case OP_SHR_R64_I64: {
					const u32 cnt = (u32)(in.operands[1].i & 0x3F);
					regs[in.operands[0].reg] >>= cnt;
					break;
				}
				case OP_SAR_R64_I64: {
					const u32 cnt = (u32)(in.operands[1].i & 0x3F);
					regs[in.operands[0].reg] = (u64)((i64)regs[in.operands[0].reg] >> cnt);
					break;
				}
				case OP_ROL_R64_I64: {
					const u32 cnt = (u32)(in.operands[1].i & 0x3F);
					const u64 v = regs[in.operands[0].reg];
					regs[in.operands[0].reg] = cnt ? ((v << cnt) | (v >> (64 - cnt))) : v;
					break;
				}
				case OP_ROR_R64_I64: {
					const u32 cnt = (u32)(in.operands[1].i & 0x3F);
					const u64 v   = regs[in.operands[0].reg];
					regs[in.operands[0].reg] = cnt ? ((v >> cnt) | (v << (64 - cnt))) : v;
					break;
				}
				case OP_LEA_R64_R64_R64_S1: regs[in.operands[0].reg] = regs[in.operands[1].reg] + regs[in.operands[2].reg]; break;
				case OP_LEA_R64_R64_R64_S2: regs[in.operands[0].reg] = regs[in.operands[1].reg] + (regs[in.operands[2].reg] << 1); break;
				case OP_LEA_R64_R64_R64_S4: regs[in.operands[0].reg] = regs[in.operands[1].reg] + (regs[in.operands[2].reg] << 2); break;
				case OP_LEA_R64_R64_R64_S8: regs[in.operands[0].reg] = regs[in.operands[1].reg] + (regs[in.operands[2].reg] << 3); break;
				case OP_COUNT: break; // unreachable, silences warning
			}
		}
	}
} // namespace so

#endif // #ifndef BATCH_RUNNER_CUH

