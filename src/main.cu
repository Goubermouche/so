#include "equivalence/rough_equivalence.cuh"
#include "candidate/generate.h"
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

so::arr<so::inst_opcode> ALL_OPCODES = {
	so::INST_MOV,
	so::INST_SUB,
	so::INST_NOT,
	so::INST_AND,
	so::INST_NEG
};

void optimize(
	const so::str& program,
	so::reg_mask live_out,
	const so::arr<u8>& allowed_regs = ALL_REG_IDS,
	const so::arr<so::inst_opcode>& allowed_opcodes = ALL_OPCODES
) {
	// print info
	so::print("> program:\n");
	so::arr<so::inst> instructions = so::parser::parse(program);

	for(const so::inst& inst : instructions) {
		inst.print();
	}

	so::print("> live out: ");
	bool first = true;

	for(u8 r = 0; r < so::REG_COUNT; ++r) {
		if(live_out & (1u << r)) {
			if(!first) {
				so::print(", ");
			}

			so::print("{}", so::reg(r).to_string());
			first = false;
		}
	}

	so::print("\n");
	so::print("> allowed regs: ");
	first = true;

	for(u8 r : allowed_regs) {
		if(!first) {
			so::print(", ");
		}

		so::print("{}", so::reg(r).to_string());
		first = false;
	}

	so::print("\n");
	so::print("> allowed opcodes: ");
	first = true;

	for(so::inst_opcode op : allowed_opcodes) {
		if(!first) {
			so::print(", ");
		}
		// TODO:
		// find name from INSTRUCTION_DB
		for(u32 i = 0; i < so::INSTRUCTION_DB_SIZE; ++i) {
			if(so::tag_opcode(so::INSTRUCTION_DB[i].tag) == op) {
				so::print("{}", so::INSTRUCTION_DB[i].name);
				break;
			}
		}

		first = false;
	}

	so::print("\n\n");

	// begin optimization
	// TODO: allow setting explicitly, this is a safe default
	so::reg_mask live_in = 0;
	for(u8 r : allowed_regs) {
		live_in |= (1u << r);
	}

	// generate test inputs
	so::arr<so::cpu_state> h_test_inputs(NUM_TESTS);
	so::generate_test_inputs(h_test_inputs.data(), NUM_TESTS, live_in);

	// generate reference outputs
	so::arr<so::cpu_state> h_ref_outputs(NUM_TESTS);

	for(u32 t = 0; t < NUM_TESTS; ++t) {
		so::cpu_state state = h_test_inputs[t];

		for(u32 i = 0; i < program.size(); ++i) {
			so::execute_inst(state, instructions[i]);
		}

		h_ref_outputs[t] = state;
	}

	// upload to GPU
	so::cpu_state* d_test_inputs;
	so::check_cuda(cudaMalloc(&d_test_inputs, NUM_TESTS * sizeof(so::cpu_state)), "alloc test inputs");
	so::check_cuda(cudaMemcpy(d_test_inputs, h_test_inputs.data(), NUM_TESTS * sizeof(so::cpu_state), cudaMemcpyHostToDevice), "copy test inputs");

	so::cpu_state* d_ref_outputs;
	so::check_cuda(cudaMalloc(&d_ref_outputs, NUM_TESTS * sizeof(so::cpu_state)), "alloc ref outputs");
	so::check_cuda(cudaMemcpy(d_ref_outputs, h_ref_outputs.data(), NUM_TESTS * sizeof(so::cpu_state), cudaMemcpyHostToDevice), "copy ref outputs");

	i32* d_result;
	so::check_cuda(cudaMalloc(&d_result, sizeof(i32)), "alloc result");

	// bounded search
	u32 baseline_len = (u32)program.size();
	auto search_start = std::chrono::high_resolution_clock::now();
	bool found = false;

	for(u32 len = 1; len < baseline_len; ++len) {
		so::arr<so::inst> current;
		so::arr<so::inst> flat_buffer;
		so::generate_candidates(current, len, allowed_opcodes, allowed_regs, flat_buffer);

		u32 num_candidates = (u32)flat_buffer.size() / len;
		so::print("> searching len {} ({} candidates)\n", len, num_candidates);

		if(num_candidates == 0) {
			continue;
		}

		so::inst* d_candidates;
		so::check_cuda(cudaMalloc(&d_candidates, flat_buffer.size() * sizeof(so::inst)), "alloc candidates");
		so::check_cuda(cudaMemcpy(d_candidates, flat_buffer.data(), flat_buffer.size() * sizeof(so::inst), cudaMemcpyHostToDevice), "copy candidates");

		i32 no_result = INT_MAX;
		so::check_cuda(cudaMemcpy(d_result, &no_result, sizeof(i32), cudaMemcpyHostToDevice), "reset result");

		u32 grid_size = (num_candidates + BLOCK_SIZE - 1) / BLOCK_SIZE;
		so::equivalence_ref_kernel<<<grid_size, BLOCK_SIZE>>>(
			d_candidates, num_candidates, len,
			d_test_inputs, d_ref_outputs, NUM_TESTS,
			live_out,
			d_result
		);

		so::check_cuda(cudaDeviceSynchronize(), "kernel sync");

		i32 h_result;
		so::check_cuda(cudaMemcpy(&h_result, d_result, sizeof(i32), cudaMemcpyDeviceToHost), "read result");

		if(h_result < (i32)num_candidates) {
			so::print("> optimization found ({} instructions):\n", len);
			u32 base = (u32)h_result * len;

			for(u32 j = 0; j < len; ++j) {
				flat_buffer[base + j].print();
			}

			found = true;
		}

		cudaFree(d_candidates);

		if(found) {
			break;
		}
	}

	auto search_end = std::chrono::high_resolution_clock::now();
	auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(search_end - search_start).count();

	if(!found) {
		so::print("> no optimization found\n");
	}

	so::print("> search took {} ms\n", (long long)ms);

	cudaFree(d_test_inputs);
	cudaFree(d_ref_outputs);
	cudaFree(d_result);
}

i32 main() {
	// input
	// program to optimize
	so::str program =
		"mov ebx, eax\n"
		"sub ebx, 1\n"
		"not ebx\n"
		"and eax, ebx\n";

	// registers that have to match reference
	so::reg_mask live_out =
		(1u << so::reg::EAX);

	optimize(program, live_out);
	return 0;
}

