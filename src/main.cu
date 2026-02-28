#include "equivalence/rough_equivalence.cuh"
#include "candidate/generate.h"
#include "assembler/parser.h"

using namespace so::type;

constexpr u32 NUM_TESTS = 256;
constexpr u32 BLOCK_SIZE = 256;

i32 main() {
	// input
	// program to optimize
	so::str program_source =
		"mov ebx, eax\n"
		"sub ebx, 1\n"
		"not ebx\n"
		"and eax, ebx\n";

	// registers that have to match reference
	so::reg_mask live_out =
		(1u << so::reg::EAX);

	// allowed registers
	so::arr<u8> reg_ids = {
		so::reg::EAX,
		so::reg::EBX,
		so::reg::ECX,
		so::reg::EDX,
		so::reg::ESI,
		so::reg::EDI,

	};

	// allowed opcodes
	so::arr<so::inst_opcode> opcodes = {
		so::INST_MOV,
		so::INST_SUB,
		so::INST_NOT,
		so::INST_AND,
		so::INST_NEG
	};


	// parse
	so::arr<so::inst> program = so::parser::parse(program_source);
	so::print("> original program:\n");

	for(const so::inst& inst : program) {
		inst.print();
	}

	// TODO: allow setting explicitly, this is a safe default
	so::reg_mask live_in = 0;
	for(u8 r : reg_ids) {
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
			so::execute_inst(state, program[i]);
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
		so::generate_candidates(current, len, opcodes, reg_ids, flat_buffer);

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
	return 0;
}

