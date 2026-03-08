#include "brute_force/brute_force.cuh"
#include "mcmc/mcmc.cuh"
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

so::arr<u64> collect_immediates(const so::arr<so::inst>& program) {
	// base set of useful constants
	so::arr<u64> imms = {
		0, 1, 2, 3, 4, 5, 7, 8, 15, 16, 31, 32,
		0xFF, 0xFFFF, 0xFFFFFFFF,
		0x80000000, 0x7FFFFFFF,
	};

	// extract immediates from the input program
	for(const so::inst& ins : program) {
		u32 op_count = so::INSTRUCTION_DB[ins.id].op_count();
		for(u32 j = 0; j < op_count; ++j) {
			if(so::INSTRUCTION_DB[ins.id].operands[j] == so::OP_I) {
				u64 v = ins.ops[j].i;
				bool found = false;
				for(u64 existing : imms) {
					if(existing == v) { found = true; break; }
				}
				if(!found) imms.push_back(v);
				// add derived values
				u64 derived[] = { v + 1, v - 1, v * 2, v / 2 };
				for(u64 d : derived) {
					bool dup = false;
					for(u64 existing : imms) {
						if(existing == d) { dup = true; break; }
					}
					if(!dup) imms.push_back(d);
				}
			}
		}
	}

	return imms;
}

so::arr<so::inst> build_inst_table(
	const so::arr<u8>& regs,
	const so::arr<u64>& immediates
) {
	so::arr<so::inst> table;
	for(u32 v = 0; v < so::INSTRUCTION_DB_SIZE; ++v) {
		so::inst_id id = (so::inst_id)v;
		u32 op_count = so::INSTRUCTION_DB[v].op_count();
		const so::inst_op* ops = so::INSTRUCTION_DB[v].operands;

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
		else if(op_count == 2 && ops[1] == so::OP_R) {
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
		else if(op_count == 2 && ops[1] == so::OP_I) {
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
		else if(op_count == 3 && ops[1] == so::OP_R && ops[2] == so::OP_I) {
			for(u8 dst : regs) {
				for(u8 src : regs) {
					for(u64 imm : immediates) {
						so::inst next{};
						next.id = id;
						next.ops[0].r = dst;
						next.ops[1].r = src;
						next.ops[2].i = imm;
						table.push_back(next);
					}
				}
			}
		}
		else if(op_count == 3 && ops[1] == so::OP_R && ops[2] == so::OP_R) {
			for(u8 dst : regs) {
				for(u8 s1 : regs) {
					for(u8 s2 : regs) {
						so::inst next{};
						next.id = id;
						next.ops[0].r = dst;
						next.ops[1].r = s1;
						next.ops[2].r = s2;
						table.push_back(next);
					}
				}
			}
		}
		else if(op_count == 4 && ops[1] == so::OP_R && ops[2] == so::OP_R && ops[3] == so::OP_I) {
			for(u8 dst : regs) {
				for(u8 s1 : regs) {
					for(u8 s2 : regs) {
						for(u64 imm : immediates) {
							so::inst next{};
							next.id = id;
							next.ops[0].r = dst;
							next.ops[1].r = s1;
							next.ops[2].r = s2;
							next.ops[3].i = imm;
							table.push_back(next);
						}
					}
				}
			}
		}
		else if(op_count == 4 && ops[1] == so::OP_R && ops[2] == so::OP_I && ops[3] == so::OP_I) {
			for(u8 dst : regs) {
				for(u8 src : regs) {
					for(u64 imm1 : immediates) {
						for(u64 imm2 : immediates) {
							so::inst next{};
							next.id = id;
							next.ops[0].r = dst;
							next.ops[1].r = src;
							next.ops[2].i = imm1;
							next.ops[3].i = imm2;
							table.push_back(next);
						}
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

	so::arr<u64> immediates = collect_immediates(instructions);
	so::print("\n> immediates: {}", (u32)immediates.size());
	for(u32 i = 0; i < immediates.size(); ++i) {
		so::print("{}{}", i == 0 ? " [" : ", ", immediates[i]);
	}
	so::print("]\n");

	so::print("> instructions: {} variants\n\n", so::INSTRUCTION_DB_SIZE);

	so::arr<so::inst> table = build_inst_table(allowed_regs, immediates);
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

		constexpr u64 BATCH_SIZE = 1ull << 24; // ~16M per batch
		u64 offset = 0;
		bool found_in_len = false;

		while(offset < total) {
			u64 remaining = total - offset;
			u64 batch = remaining < BATCH_SIZE ? remaining : BATCH_SIZE;
			u64 grid = (batch + BLOCK_SIZE - 1) / BLOCK_SIZE;

			brute_force_search<<<grid, BLOCK_SIZE>>>(
				d_table, static_cast<u32>(table.size()), len, total,
				d_test_inputs, d_ref_outputs, NUM_TESTS,
				live_out, d_result, offset
			);

			so::check_cuda(cudaDeviceSynchronize(), "kernel sync");

			u64 h_result;
			so::check_cuda(cudaMemcpy(&h_result, d_result, sizeof(u64), cudaMemcpyDeviceToHost), "read result");

			if(h_result < total) {
				so::print("\r> len {}: 100.0%%\n", len);
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
				found_in_len = true;
				break;
			}

			offset += batch;
			double pct = 100.0 * (double)offset / (double)total;
			if(pct > 100.0) pct = 100.0;
			printf("\r> len %u: %.1f%%", len, pct);
			fflush(stdout);
		}

		if(!found_in_len) {
			printf("\r> len %u: 100.0%%\n", len);
		}

		if(found) break;
	}

	if(!found) {
		auto search_end = std::chrono::high_resolution_clock::now();
		auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(search_end - search_start).count();
		so::print("> no optimization found\n");
		so::print("> search took {} ms\n", (long long)ms);
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
