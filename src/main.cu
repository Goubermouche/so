#include "equivalence/search.cuh"
#include "assembler/parser.h"

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

void verify(
	const so::arr<so::inst>& original,
	const so::arr<so::inst>& optimized,
	so::reg_mask live_out,
	u32 num_tests = 1000000
) {
	u64 seed = 0xA5A5A5A5A5A5A5A5ull;
	u32 failures = 0;

	for(u32 t = 0; t < num_tests; ++t) {
		so::cpu_state input{};
		for(u8 r = 0; r < so::REG_COUNT; ++r) {
			seed = seed * 6364136223846793005ull + 1442695040888963407ull;
			input.regs[r] = static_cast<u32>(seed >> 16);
		}

		so::cpu_state state_orig = input;
		so::cpu_state state_opt = input;

		for(const so::inst& i : original) {
			so::execute_inst(state_orig, i);
		}
		for(const so::inst& i : optimized) {
			so::execute_inst(state_opt, i);
		}

		so::reg_mask mask = live_out;
		while(mask) {
			u32 r = __builtin_ctz(mask);
			if(state_orig.regs[r] != state_opt.regs[r]) {
				if(failures < 3) {
					printf("> mismatch test %u:\n  input:     ", t);
					for(u8 i = 0; i < so::REG_COUNT; ++i) {
						printf("%s=0x%08X ", so::reg(i).to_string(), input.regs[i]);
					}
					printf("\n  original:  %s=0x%08X\n", so::reg(r).to_string(), state_orig.regs[r]);
					printf("  optimized: %s=0x%08X\n", so::reg(r).to_string(), state_opt.regs[r]);
				}
				++failures;
				break;
			}
			mask &= mask - 1;
		}
	}

	if(failures == 0) {
		so::print("> verified: {}/{} tests passed\n", num_tests, num_tests);
	} else {
		so::print("> failed: {}/{} tests failed (showing first 3)\n", failures, num_tests);
	}
}

so::arr<so::inst> build_inst_table(
	const so::arr<u8>& regs
) {
	static const so::arr<u64> immediates = {0ull, 1ull, 2ull};
	so::arr<so::inst> table;

	for(u32 v = 0; v < so::INSTRUCTION_DB_SIZE; ++v) {
		so::inst_id id = (so::inst_id)v;
		u32 op_count = so::INSTRUCTION_DB[v].op_count();

		if(op_count == 0) {
			so::inst next{};
			next.id = id;
			table.push_back(next);
		}
		else if(op_count == 1) {
			for(u8 dst : regs) {
				so::inst next{};
				next.id = id;
				next.ops[0].r = dst;
				table.push_back(next);
			}
		}
		else if(so::INSTRUCTION_DB[v].operands[1] == so::OP_R) {
			for(u8 dst : regs) {
				for(u8 src : regs) {
					so::inst next{};
					next.id = id;
					next.ops[0].r = dst;
					next.ops[1].r = src;
					table.push_back(next);
				}
			}
		}
		else if(so::INSTRUCTION_DB[v].operands[1] == so::OP_I) {
			for(u8 dst : regs) {
				for(u64 imm : immediates) {
					so::inst next{};
					next.id = id;
					next.ops[0].r = dst;
					next.ops[1].i = imm;
					table.push_back(next);
				}
			}
		}
	}

	return table;
}

void optimize(
	const so::str& program,
	so::reg_mask live_out,
	const so::arr<u8>& allowed_regs = ALL_REG_IDS
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

	so::print("\n> instructions: {} variants\n\n", so::INSTRUCTION_DB_SIZE);

	so::arr<so::inst> table = build_inst_table(allowed_regs);
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
			so::arr<so::inst> optimized;
			u64 tmp = h_result;
			for(u32 i = 0; i < len; ++i) {
				table[tmp % table.size()].print();
				optimized.push_back(table[tmp % table.size()]);
				tmp /= table.size();
			}
			auto search_end = std::chrono::high_resolution_clock::now();
			auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(search_end - search_start).count();
			so::print("> search took {} ms\n", (long long)ms);
			verify(instructions, optimized, live_out);
			found = true;
			break;
		}
	}



	if(!found) {
		so::print("> no optimization found\n");
	}

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
