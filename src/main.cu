#include "equivalence/search.cuh"
#include "assembler/parser.h"
#include <chrono>
#include <climits>
#include <limits>

using namespace so::type;

constexpr u32 NUM_TESTS = 256;
constexpr u32 BLOCK_SIZE = 256;

so::arr<u8> ALL_REG_IDS = {
	so::reg::EAX,
	so::reg::EBX,
	so::reg::ECX,
	so::reg::EDX,
	so::reg::ESI,
	so::reg::EDI,
};

so::arr<so::inst_opcode> ALL_OPCODES = {
	so::INST_MOV,
	so::INST_SUB,
	so::INST_NOT,
	so::INST_AND,
	so::INST_NEG,
	so::INST_OR,
	so::INST_XOR,
	so::INST_SHL,
	so::INST_SHR,
};

so::arr<so::inst> build_inst_table(
	const so::arr<so::inst_opcode>& opcodes,
	const so::arr<u8>& regs
) {
	static const so::arr<u64> immediates = {0ull, 1ull, 2ull};
	so::arr<so::inst> table;

	for(so::inst_opcode op : opcodes) {
		for(u32 v = 0; v < so::INSTRUCTION_DB_SIZE; ++v) {
			if(so::tag_opcode(so::INSTRUCTION_DB[v].tag) != op) {
				continue;
			}

			so::inst_tag tag = so::INSTRUCTION_DB[v].tag;
			u32 op_count = so::tag_op_count(tag);

			if(op_count == 0) {
				so::inst next{};
				next.tag = tag;
				table.push_back(next);
			}
			else if(op_count == 1) {
				for(u8 dst : regs) {
					so::inst next{};
					next.tag = tag;
					next.ops[0].r = dst;
					table.push_back(next);
				}
			}
			else if(so::tag_op(tag, 1) == so::OP_R) {
				for(u8 dst : regs) {
					for(u8 src : regs) {
						so::inst next{};
						next.tag = tag;
						next.ops[0].r = dst;
						next.ops[1].r = src;
						table.push_back(next);
					}
				}
			}
			else if(so::tag_op(tag, 1) == so::OP_I) {
				for(u8 dst : regs) {
					for(u64 imm : immediates) {
						so::inst next{};
						next.tag = tag;
						next.ops[0].r = dst;
						next.ops[1].i = imm;
						table.push_back(next);
					}
				}
			}
		}
	}

	return table;
}

void optimize(
	const so::str& program,
	so::reg_mask live_out,
	const so::arr<u8>& allowed_regs = ALL_REG_IDS,
	const so::arr<so::inst_opcode>& allowed_opcodes = ALL_OPCODES
) {
	so::print("> program:\n");
	so::arr<so::inst> instructions = so::parser::parse(program);

	for(const so::inst& inst : instructions) {
		inst.print();
	}

	so::print("> live out: ");
	bool first = true;
	for(u8 r = 0; r < so::REG_COUNT; ++r) {
		if(live_out & (1u << r)) {
			if(!first) so::print(", ");
			so::print("{}", so::reg(r).to_string());
			first = false;
		}
	}

	so::print("\n> allowed regs: ");
	first = true;
	for(u8 r : allowed_regs) {
		if(!first) so::print(", ");
		so::print("{}", so::reg(r).to_string());
		first = false;
	}

	so::print("\n> allowed opcodes: ");
	first = true;
	for(so::inst_opcode op : allowed_opcodes) {
		if(!first) so::print(", ");
		for(u32 i = 0; i < so::INSTRUCTION_DB_SIZE; ++i) {
			if(so::tag_opcode(so::INSTRUCTION_DB[i].tag) == op) {
				so::print("{}", so::INSTRUCTION_DB[i].name);
				break;
			}
		}
		first = false;
	}
	so::print("\n\n");

	so::arr<so::inst> table = build_inst_table(allowed_opcodes, allowed_regs);
	so::print("> instruction table: {} entries\n", (u32)table.size());

	so::reg_mask live_in = 0;
	for(u8 r : allowed_regs) {
		live_in |= (1u << r);
	}

	so::arr<so::cpu_state> h_test_inputs(NUM_TESTS);
	so::generate_test_inputs(h_test_inputs.data(), NUM_TESTS, live_in);

	so::arr<so::cpu_state> h_ref_outputs(NUM_TESTS);
	for(u32 t = 0; t < NUM_TESTS; ++t) {
		so::cpu_state state = h_test_inputs[t];
		for(u32 i = 0; i < instructions.size(); ++i) {
			so::execute_inst(state, instructions[i]);
		}
		h_ref_outputs[t] = state;
	}

	so::inst* d_table;
	so::check_cuda(cudaMalloc(&d_table, table.size() * sizeof(so::inst)), "alloc inst table");
	so::check_cuda(cudaMemcpy(d_table, table.data(), table.size() * sizeof(so::inst), cudaMemcpyHostToDevice), "copy inst table");

	so::cpu_state* d_test_inputs;
	so::check_cuda(cudaMalloc(&d_test_inputs, NUM_TESTS * sizeof(so::cpu_state)), "alloc test inputs");
	so::check_cuda(cudaMemcpy(d_test_inputs, h_test_inputs.data(), NUM_TESTS * sizeof(so::cpu_state), cudaMemcpyHostToDevice), "copy test inputs");

	so::cpu_state* d_ref_outputs;
	so::check_cuda(cudaMalloc(&d_ref_outputs, NUM_TESTS * sizeof(so::cpu_state)), "alloc ref outputs");
	so::check_cuda(cudaMemcpy(d_ref_outputs, h_ref_outputs.data(), NUM_TESTS * sizeof(so::cpu_state), cudaMemcpyHostToDevice), "copy ref outputs");

	u64* d_result;
	so::check_cuda(cudaMalloc(&d_result, sizeof(u64)), "alloc result");

	u32 baseline_len = static_cast<u32>(instructions.size());
	auto search_start = std::chrono::high_resolution_clock::now();
	bool found = false;

	for(u32 len = 1; len < baseline_len; ++len) {
		u64 total = 1;

		for(u32 i = 0; i < len; ++i) {
			total *= table.size();
		}

		so::print("> searching len {} ({} programs)\n", len, total);

		u64 no_result = std::numeric_limits<u64>::max();
		so::check_cuda(cudaMemcpy(d_result, &no_result, sizeof(u64), cudaMemcpyHostToDevice), "reset result");
		u64 grid = (total + BLOCK_SIZE - 1) / BLOCK_SIZE;
		search_kernel<<<grid, BLOCK_SIZE>>>(
			d_table, static_cast<u32>(table.size()), len, total,
			d_test_inputs, d_ref_outputs, NUM_TESTS,
			live_out, d_result
		);

		so::check_cuda(cudaDeviceSynchronize(), "kernel sync");

		u64 h_result;
		so::check_cuda(cudaMemcpy(&h_result, d_result, sizeof(u64), cudaMemcpyDeviceToHost), "read result");

		if(h_result < total) {
			so::print("> optimization found ({} instructions):\n", len);
			u64 tmp = h_result;
			for(u32 i = 0; i < len; ++i) {
				table[tmp % table.size()].print();
				tmp /= table.size();
			}

			found = true;
			break;
		}
	}

	auto search_end = std::chrono::high_resolution_clock::now();
	auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(search_end - search_start).count();

	if(!found) {
		so::print("> no optimization found\n");
	}
	so::print("> search took {} ms\n", (long long)ms);

	cudaFree(d_table);
	cudaFree(d_test_inputs);
	cudaFree(d_ref_outputs);
	cudaFree(d_result);
}
i32 main() {
	so::str program =
		"mov ebx, eax\n"
		"shl ebx, 1\n"
		"mov ecx, eax\n"
		"neg ecx\n"
		"sub ebx, ecx\n";
	so::reg_mask live_out =
		(1u << so::reg::EBX);
	optimize(program, live_out);
	return 0;
}
