#include "optimize/optimize.h"
#include "cpu/instruction.cuh"
#include "cpu/program.h"
#include "optimize/enumerate.cuh"
#include "optimize/filter.cuh"
#include "smt/smt.h"
#include "util/type.h"

void optimizer_make_default_options(OptimizerOptions* opt) {
	opt->seed = 1;
	opt->ext_mask = ExtRV32I;
	opt->batch_size = 4000000;
	opt->max_cegis_iters = 8;
}

i32 optimizer_make(Optimizer* optimizer, OptimizerOptions* opt) {
	optimizer->opt = opt;
	optimizer->total_candidates = 0;
	optimizer->filter_passes = 0;
	optimizer->smt_calls = 0;
	optimizer->ms_enum = 0.0;
	optimizer->ms_filter = 0.0;
	optimizer->ms_smt = 0.0;
	optimizer->ms_total = 0.0;

	if(filter_make(&optimizer->filter, optimizer->opt->batch_size)) {
		fprintf(stderr, "error: filter::init failed\n");
		return 1;
	}

	if(enum_make(&optimizer->enumerate, optimizer->opt->batch_size)) {
		fprintf(stderr, "error: enum_ctx::init failed\n");
		return 1;
	}

	return 0;
}

void optimizer_free(Optimizer* optimizer) {
	enum_free(&optimizer->enumerate);
	filter_free(&optimizer->filter);
}

i32 optimizer_run(Optimizer* optimizer, Program* program) {
	optimizer->prog = program;
	optimizer->live_out = program_get_live_out(program);
	optimizer->live_in = program_get_live_in(program);

	optimizer_log_startup(optimizer);
	optimizer_init_tests(optimizer);
	printf("begin search\n");

	f64 t0 = get_time_ms();
	b32 found = false;

	for(u32 len = 1; len <= MaxProgramLen; ++len) {
		printf("  searching length %u\n", len);
		if(optimizer_run_length(optimizer, len)) {
			found = true;
			break;
		}
	}

	optimizer->ms_total = get_time_ms() - t0;

	optimizer_log_results(optimizer, found);
	optimizer_log_stats(optimizer);
	return 0;
}

b32 optimizer_run_length(Optimizer* optimizer, u32 len) {
	u32 effective_mask = optimizer->opt->ext_mask | ExtRV32I;
	if(effective_mask & ExtRV64M) effective_mask |= ExtRV32M;

	EnumOpcodePool opcodes;
	EnumImmPool immediates;
	enum_make_opcode_pool(&opcodes, effective_mask);
	enum_make_imm_pool(&immediates);

	u32 max_scratch = MIN(32, 5 + len);
	u32 iter = 0;

	// CEGIS main loop for instructions of length 'len', iterates until we either
	// find a satisfactory program (SMT_State proven equivalence), or until we don't
	// find any new counterexammples
	while(iter < optimizer->opt->max_cegis_iters) {
		const u32 prev_counterexample_count = optimizer->counterexample_count;
		const f64 t0 = get_time_ms();
		EnumOptions cfg;
		cfg.pool = &opcodes;
		cfg.imms = &immediates;
		cfg.live_in_mask = optimizer->live_in;
		cfg.live_out_mask = optimizer->live_out;
		cfg.prog_len = len;
		cfg.max_scratch = max_scratch;
		cfg.cap = optimizer->opt->batch_size;
		EnumProgram* p = nullptr;
		u64 p_cnt = 0;

		// generate candidates
		enum_run(&optimizer->enumerate, &cfg);
		p = optimizer->enumerate.out_d_cands;
		p_cnt = optimizer->enumerate.out_n_cands;
		optimizer->ms_enum += get_time_ms() - t0;
		printf("    iter %u (%.2fM cand)\n", iter + 1, (f64)p_cnt / 1e6);

		if(p_cnt == 0) { return false; }
		// filter candidates,
		b32 found_solution = optimizer_filter_batch(optimizer, p, p_cnt, len);
		if(found_solution) { return true; }
		// exit if we run out of new counterexamples
		if(optimizer->counterexample_count == prev_counterexample_count) { return false; }
		++iter;
	}

	printf("    iter limit hit (len: %u)\n", len);
	return false;
}

b32 optimizer_filter_batch(Optimizer* optimizer, EnumProgram* p, u64 p_cnt, u32 len) {
	if(p_cnt == 0) { return false; }
	arena scratch;
	FilterOptions cfg;
	cfg.live_mask = optimizer->live_out;
	cfg.prog_len = len;
	cfg.candidates = (Instruction*)p;
	cfg.n_candidates = p_cnt;
	cfg.test_in = optimizer->test_in;
	cfg.target_out = optimizer->target_out;
	u8* pass_counts = scratch.push<u8>(p_cnt);

	// run mass filter - remove the majority of candidate programs by verifying
	// their correctness against a set of random and counterexample tests
	f64 t0_filter = get_time_ms();
	filter_run(&optimizer->filter, &cfg, pass_counts);
	optimizer->ms_filter += get_time_ms() - t0_filter;
	optimizer->total_candidates += p_cnt;
	optimizer->filter_passes++;

	// go through our candidates, if they passed the test set we verify them
	// via an SMT_State solver
	for(u64 i = 0; i < p_cnt; ++i) {
		if(pass_counts[i] == FilterTestCount) {
			// pull the candidate instructions
			Instruction survivor_inst[MaxProgramLen];
			dtoh_memcpy(survivor_inst, p + i, sizeof(EnumProgram));
			const f64 t0_smt = get_time_ms();
			Program survivor = {survivor_inst, len};
			// verify via an SMT_State solver
			SMT_Result res = smt_equiv(*optimizer->prog, survivor, optimizer->live_out);
			optimizer->ms_smt += get_time_ms() - t0_smt;
			++optimizer->smt_calls;

			if(res.type == SMT_ResultType_EQUIVALENT) {
				// equivalent Program
				Instruction* dst = optimizer->mem.push<Instruction>(len);
				memcpy(dst, survivor_inst, sizeof(Instruction) * len);
				optimizer->best = {dst, len};
				return true;
			} else if(res.type == SMT_ResultType_COUNTEREXAMPLE) {
				// add the counterexample (round robin), then abort this batch
				const u32 slot = 16 + (optimizer->counterexample_count % 16);
				optimizer->counterexample_count++;
				optimizer->test_in[slot] = res.counterexample;
				optimizer->target_out[slot] = filter_run_host(optimizer->prog, &res.counterexample);
				return false;
			}
		}
	}

	return false;
}

void optimizer_log_startup(Optimizer* optimizer) {
	arena scratch;

	printf("source (len: %u):\n", optimizer->prog->size);
	string src = program_to_string(optimizer->prog, &scratch);
	printf("%s", (const c8*)src.ptr);
	printf("live-in:  { ");
	opt_print_reg_mask(optimizer->live_in);
	printf(" }\n");
	printf("live-out: { ");
	opt_print_reg_mask(optimizer->live_out);
	printf(" }\n");
	u32 effective_mask = optimizer->opt->ext_mask | ExtRV32I;
	if(effective_mask & ExtRV64M) effective_mask |= ExtRV32M;
	printf("extensions: ");
	b32 first = true;
	for(u32 i = 0; i < DatabaseExtensionCount; ++i) {
		if(effective_mask & DatabaseExtensionBits[i]) {
			printf("%s%s", first ? "" : ", ", DatabaseExtensionNames[i].ptr);
			first = false;
		}
	}
	printf("\n");
	printf("max prog len: %u\n", MaxProgramLen);
	printf("batch size: %zu cands\n", optimizer->opt->batch_size);
}

void optimizer_log_results(Optimizer* optimizer, b32 found) {
	if(!found) {
		printf("done: no optimizations found (len: %u)\n", MaxProgramLen);
		return;
	}

	printf("done: optimization found (len: %u):\n", optimizer->best.size);
	string s = program_to_string(&optimizer->best, &optimizer->mem);
	printf("%s", (const c8*)s.ptr);
}

void optimizer_log_stats(Optimizer* optimizer) {
	printf("statistics:\n");
	printf("  candidates:  %.2fM\n", (f64)optimizer->total_candidates / 1e6);
	const f64 safe_ms_enum = (optimizer->ms_enum > 0.0) ? optimizer->ms_enum : 0.001;
	const f64 eps = (f64)optimizer->total_candidates / (safe_ms_enum / 1000.0);
	const f64 epsm = eps / 1e6;
	printf("  enum time:   %.2fms (%.2fM cand/sec)\n", optimizer->ms_enum, epsm);
	const f64 safe_ms_filter = (optimizer->ms_filter > 0.0) ? optimizer->ms_filter : 0.001;
	const f64 fps = (f64)optimizer->total_candidates / (safe_ms_filter / 1000.0);
	const f64 fpsm = fps / 1e6;
	printf("  filter time: %.2fms (%.2fM cand/sec)\n", optimizer->ms_filter, fpsm);
	printf("  smt time:    %.2fms (%zu calls)\n", optimizer->ms_smt, optimizer->smt_calls);
	printf("  total time:  %.2fms\n", optimizer->ms_total);
}

void optimizer_init_tests(Optimizer* optimizer) {
	// 32 random test vectors at start, the CEGIS loop adds counterexamples, which
	// are placed into the last 16 slots (round robin)
	u64 s = optimizer->opt->seed ^ 0x9E3779B97F4A7C15ull;

	for(u32 t = 0; t < FilterTestCount; ++t) {
		CpuState in = {};

		for(u32 i = 0; i < 32; ++i) {
			s ^= s >> 30;
			s *= 0xBF58476D1CE4E5B9ull;
			s ^= s >> 27;
			s *= 0x94D049BB133111EBull;
			s ^= s >> 31;
			in.regs[i] = s;
		}

		in.regs[0] = 0; // x0 invariant
		optimizer->test_in[t] = in;
		optimizer->target_out[t] = filter_run_host(optimizer->prog, &in);
	}
}