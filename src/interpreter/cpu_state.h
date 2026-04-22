#ifndef CPU_STATE_H
#define CPU_STATE_H

#include "util/type.h"

namespace so {
	enum reg_index {
		REG_RAX = 0,
		REG_RBX,
		REG_RCX,
		REG_RDX,
		REG_RSI,
		REG_RDI,
		REG_RBP,
		REG_RSP,
		REG_R8,
		REG_R9,
		REG_R10,
		REG_R11,
		REG_R12,
		REG_R13,
		REG_R14,
		REG_R15
	};

	struct cpu_state {
		u64 regs[16];

		inline void set_r64(reg_index dest, u64 value) { regs[dest] = value; }
		inline u64 get_r64(reg_index src) { return regs[src]; }

		// instructions

		inline void mov_r64_v64(reg_index dest, u64 value) {
			set_r64(dest, value);
		}

		inline void add_r64_v64(reg_index dest, u64 value) {
			u64 s = value;
			u64 d = get_r64(dest);
			u64 r = d + s;
			set_r64(dest, r);
		}

		inline void neg_r64(reg_index dest) {
			set_r64(dest, -get_r64(dest));
		}

		inline void and_r64_v64(reg_index dest, u64 value) {
			u64 s = value;
			u64 d = get_r64(dest);
			u64 r = d & s;
			set_r64(dest, r);
		}

		inline void xor_r64_v64(reg_index dest, u64 value) {
			u64 s = value;
			u64 d = get_r64(dest);
			u64 r = d ^ s;
			set_r64(dest, r);
		}

		inline void not_r64(reg_index dest) {
			set_r64(dest, ~get_r64(dest));
		}
	};
}

#endif // CPU_STATE_H

