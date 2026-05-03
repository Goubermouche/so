#ifndef CPU_CUH
#define CPU_CUH

#include "utl/device.h"

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

	SO_HD const char* reg_name(u32 r) {
		switch(r) {
			case 0:  return "rax";
			case 1:  return "rbx";
			case 2:  return "rcx";
			case 3:  return "rdx";
			case 4:  return "rsi";
			case 5:  return "rdi";
			case 6:  return "rbp";
			case 7:  return "rsp";
			case 8:  return "r8";
			case 9:  return "r9";
			case 10: return "r10";
			case 11: return "r11";
			case 12: return "r12";
			case 13: return "r13";
			case 14: return "r14";
			case 15: return "r15";
			default: return "?";
		}
	}

	struct cpu_state {
		u64 regs[16];
	};
} // namespace so

#endif // #ifndef CPU_CUH

