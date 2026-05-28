#ifndef EXT_DATABASE_CUH
#define EXT_DATABASE_CUH

#include "cpu/instruction.cuh"
#include "extensions/rv32i/opcodes.def"
#include "extensions/rv32m/opcodes.def"
#include "extensions/rv64i/opcodes.def"
#include "extensions/rv64m/opcodes.def"

#define MaxProgramLen 8

#define DatabaseExtensionList(X)                                                                   \
	X(RV32I, "rv32i", 0)                                                                             \
	X(RV64I, "rv64i", 1)                                                                             \
	X(RV32M, "rv32m", 2)                                                                             \
	X(RV64M, "rv64m", 3)

#define DatabaseExtensionOpcodeList(X)                                                             \
	ExtensionsRV32IOpcodes(X) ExtensionsRV64IOpcodes(X) ExtensionsRV32MOpcodes(X)                    \
		ExtensionsRV64MOpcodes(X)

// ExtRV32I is the base ISA and is always implied
// rv64-prefixed extensions extend their rv32 counterpart and require
// it to be enabled. The optimizer's pool builder enforces this implicitly
typedef enum DatabaseExtensionBitsEnum {
#define X(tag, dir, bit) Ext##tag = 1u << (bit),
	DatabaseExtensionList(X)
#undef X
} DatabaseExtensionBitsEnum;

// array of all extension directory names
inline const S8 DatabaseExtensionNames[] = {
#define X(tag, dir, bit) S8(dir),
	DatabaseExtensionList(X)
#undef X
};

inline const U32 DatabaseExtensionBits[] = {
#define X(tag, dir, bit) (1u << (bit)),
	DatabaseExtensionList(X)
#undef X
};

#define DatabaseExtensionCount (sizeof(DatabaseExtensionNames) / sizeof(DatabaseExtensionNames[0]))

// typedef in instruction.cuh
typedef enum InstructionOpcodeEnum {
#define X(tag, mnemonic, shape, comm) InstructionOpcode_##tag,
	DatabaseExtensionOpcodeList(X)
#undef X
		InstructionOpcode_Nop,
	InstructionOpcode_Count,
} InstructionOpcodeEnum;

typedef struct InstructionDB {
	InstructionInfo row[InstructionOpcode_Count];
} InstructionDB;

extern InstructionDB instruction_db_host;

void instruction_db_load();

#ifdef __CUDACC__
__device__ InstructionInfo* instruction_db_find_info_dev(InstructionOpcode op);
#endif // #ifdef __CUDACC__

HostDevice InstructionInfo* instruction_db_find_info(InstructionOpcode op) {
#ifdef __CUDA_ARCH__
	return instruction_db_find_info_dev(op);
#else
	return &instruction_db_host.row[op];
#endif // #ifdef __CUDA_ARCH__
}

InstructionOpcode instruction_db_find(S8 name, InstructionOperandType* ops, U8 op_cnt);

#endif // #ifndef EXT_DATABASE_CUH