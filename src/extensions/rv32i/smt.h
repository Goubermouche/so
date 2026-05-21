#ifndef EXT_RV32I_SMT_CUH
#define EXT_RV32I_SMT_CUH

#include "smt/smt.h"

inline b32 ext_rv32i_smt(z3::context& ctx, SMT_State& s, const SMT_Decode& d) {
	switch(d.op) {
		case InstructionOpcode_Add:   WR(A + B);
		case InstructionOpcode_Sub:   WR(A - B);
		case InstructionOpcode_Xor:   WR(A ^ B);
		case InstructionOpcode_Or:    WR(A | B);
		case InstructionOpcode_And:   WR(A & B);
		case InstructionOpcode_Sll:   WR(z3::shl(A, smt_low6(ctx, B)));
		case InstructionOpcode_Srl:   WR(z3::lshr(A, smt_low6(ctx, B)));
		case InstructionOpcode_Sra:   WR(z3::ashr(A, smt_low6(ctx, B)));
		case InstructionOpcode_Slt:   WR(smt_ite_bool_to_bv64(ctx, z3::slt(A, B)));
		case InstructionOpcode_Sltu:  WR(smt_ite_bool_to_bv64(ctx, z3::ult(A, B)));
		case InstructionOpcode_Addi:  WR(A + d.imm);
		case InstructionOpcode_Xori:  WR(A ^ d.imm);
		case InstructionOpcode_Ori:   WR(A | d.imm);
		case InstructionOpcode_Andi:  WR(A & d.imm);
		case InstructionOpcode_Slli:  WR(z3::shl(A, smt_low6(ctx, d.imm)));
		case InstructionOpcode_Srli:  WR(z3::lshr(A, smt_low6(ctx, d.imm)));
		case InstructionOpcode_Srai:  WR(z3::ashr(A, smt_low6(ctx, d.imm)));
		case InstructionOpcode_Slti:  WR(smt_ite_bool_to_bv64(ctx, z3::slt(A, d.imm)));
		case InstructionOpcode_Sltiu: WR(smt_ite_bool_to_bv64(ctx, z3::ult(A, d.imm)));
		case InstructionOpcode_Lui:   WR(smt_sext_w(ctx, z3::shl(d.imm, smt_bv64(ctx, 12))));
	}
	return false;
}

#endif // EXT_RV32I_SMT_CUH
