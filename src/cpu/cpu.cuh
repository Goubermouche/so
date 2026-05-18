#ifndef CPU_CPU_CUH
#define CPU_CPU_CUH

#include "util/device.h"

namespace sup {
enum reg_index {
	REG_X0 = 0,
	REG_X1,
	REG_X2,
	REG_X3,
	REG_X4,
	REG_X5,
	REG_X6,
	REG_X7,
	REG_X8,
	REG_X9,
	REG_X10,
	REG_X11,
	REG_X12,
	REG_X13,
	REG_X14,
	REG_X15,
	REG_X16,
	REG_X17,
	REG_X18,
	REG_X19,
	REG_X20,
	REG_X21,
	REG_X22,
	REG_X23,
	REG_X24,
	REG_X25,
	REG_X26,
	REG_X27,
	REG_X28,
	REG_X29,
	REG_X30,
	REG_X31,
	REG_COUNT = 32,
};

struct cpu_state {
	u64 regs[32];
};

SO_HD const c8* reg_name(u32 r) {
	switch(r) {
		case 0: return "x0";
		case 1: return "x1";
		case 2: return "x2";
		case 3: return "x3";
		case 4: return "x4";
		case 5: return "x5";
		case 6: return "x6";
		case 7: return "x7";
		case 8: return "x8";
		case 9: return "x9";
		case 10: return "x10";
		case 11: return "x11";
		case 12: return "x12";
		case 13: return "x13";
		case 14: return "x14";
		case 15: return "x15";
		case 16: return "x16";
		case 17: return "x17";
		case 18: return "x18";
		case 19: return "x19";
		case 20: return "x20";
		case 21: return "x21";
		case 22: return "x22";
		case 23: return "x23";
		case 24: return "x24";
		case 25: return "x25";
		case 26: return "x26";
		case 27: return "x27";
		case 28: return "x28";
		case 29: return "x29";
		case 30: return "x30";
		case 31: return "x31";
		default: return "?";
	}
}
} // namespace sup

#endif // #ifndef CPU_CPU_CUH
