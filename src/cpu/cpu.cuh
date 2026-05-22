#ifndef CPU_CPU_CUH
#define CPU_CPU_CUH

#include "util/device.cuh"

typedef enum Reg : U32 {
	Reg_X0 = 0,
	Reg_X1,
	Reg_X2,
	Reg_X3,
	Reg_X4,
	Reg_X5,
	Reg_X6,
	Reg_X7,
	Reg_X8,
	Reg_X9,
	Reg_X10,
	Reg_X11,
	Reg_X12,
	Reg_X13,
	Reg_X14,
	Reg_X15,
	Reg_X16,
	Reg_X17,
	Reg_X18,
	Reg_X19,
	Reg_X20,
	Reg_X21,
	Reg_X22,
	Reg_X23,
	Reg_X24,
	Reg_X25,
	Reg_X26,
	Reg_X27,
	Reg_X28,
	Reg_X29,
	Reg_X30,
	Reg_X31,
	Reg_Count = 32,
} Reg;

typedef struct CpuState {
	U64 regs[32];
} CpuState;

HostDevice const C8* reg_name(U32 r) {
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

inline void opt_print_reg_mask(U64 mask) {
	B32 first = true;

	for(U32 r = 0; r < 32; ++r) {
		if(mask & (1ull << r)) {
			printf("%s%s", first ? "" : ",", reg_name(r));
			first = false;
		}
	}

	if(first) { printf("(none)"); }
}

#endif // #ifndef CPU_CPU_CUH
