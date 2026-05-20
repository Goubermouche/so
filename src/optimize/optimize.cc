#include "optimize/optimize.h"
#include "cpu/instruction.cuh"
#include "cpu/program.h"
#include "optimize/batch_runner.cuh"
#include "optimize/filter.cuh"
#include "smt/smt.h"
#include "util/type.h"

namespace sup {
void optimizer::run(const program& prog, const options& opt) {
	optimizer optimizer(prog, opt);
	optimizer.run();
}

optimizer::optimizer(const program& prog, const options& opt)
	: prog(prog), opt(opt) {
	live_out = prog.get_live_out();
	live_in = prog.get_live_in();
}

optimizer::~optimizer() {
	opt_enum_ctx_free(&enumerate);
	opt_filter_free(&filter);
}

b32 optimizer::run() {
	f64 t0 = get_time_ms();
	log_startup();
	init_tests();

	if(opt_filter_make(&filter, opt.batch_size)) {
		fprintf(stderr, "error: filter::init failed\n");
		return true;
	}

	if(opt_enum_make(&enumerate, opt.batch_size)) {
		fprintf(stderr, "error: enum_ctx::init failed\n");
		return true;
	}

	printf("begin search\n");
	b32 found = false;
	for(u32 len = 1; len <= OPT_PROGRAM_LEN; ++len) {
		printf("  searching length %u\n", len);
		if(run_length(len)) {
			found = true;
			break;
		}
	}

	ms_total = get_time_ms() - t0;
	log_results(found);
	log_stats();
	return false;
}

b32 optimizer::run_length(u32 len) {
	u32 effective_mask = opt.ext_mask | EXT_RV32I;
	if(effective_mask & EXT_RV64M) effective_mask |= EXT_RV32M;

	const opt_opcode_pool opcodes = opt_build_opcode_pool(effective_mask);
	const opt_imm_pool immediates = opt_build_imm_pool();

	u32 max_scratch = MIN(32, 5 + len);
	u32 iter = 0;

	// CEGIS main loop for instructions of length 'len', iterates until we either
	// find a satisfactory program (SMT proven equivalence), or until we don't
	// find any new counterexammples
	while(iter < opt.max_cegis_iters) {
		const u32 prev_counterexample_count = counterexample_count;
		const f64 t0 = get_time_ms();
		opt_enum_cfg cfg;
		cfg.pool = &opcodes;
		cfg.imms = &immediates;
		cfg.live_in_mask = live_in;
		cfg.live_out_mask = live_out;
		cfg.prog_len = len;
		cfg.max_scratch = max_scratch;
		cfg.cap = opt.batch_size;
		opt_program* p = nullptr;
		u64 p_cnt = 0;

		// generate candidates
		opt_enumerate(&enumerate, &cfg);
		p = enumerate.out_d_cands;
		p_cnt = enumerate.out_n_cands;
		ms_enum += get_time_ms() - t0;
		printf("    iter %u (%.2fM cand)\n", iter + 1, (f64)p_cnt / 1e6);

		if(p_cnt == 0) { return false; }
		// filter candidates,
		b32 found_solution = filter_batch(p, p_cnt, len);
		if(found_solution) { return true; }
		// exit if we run out of new counterexamples
		if(counterexample_count == prev_counterexample_count) { return false; }
		++iter;
	}

	printf("    iter limit hit (len: %u)\n", len);
	return false;
}

b32 optimizer::filter_batch(const opt_program* p, u64 p_cnt, u32 len) {
	if(p_cnt == 0) { return false; }
	arena scratch;
	opt_filter_cfg cfg;
	cfg.live_mask = live_out;
	cfg.prog_len = len;
	cfg.candidates = (const inst*)p;
	cfg.n_candidates = p_cnt;
	cfg.test_in = test_in;
	cfg.target_out = target_out;
	u8* pass_counts = scratch.push<u8>(p_cnt);

	// run mass filter - remove the majority of candidate programs by verifying
	// their correctness against a set of random and counterexample tests
	f64 t0_filter = get_time_ms();
	opt_filter_run(&filter, &cfg, pass_counts);
	ms_filter += get_time_ms() - t0_filter;
	total_candidates += p_cnt;
	filter_passes++;

	// go through our candidates, if they passed the test set we verify them
	// via an SMT solver
	for(u64 i = 0; i < p_cnt; ++i) {
		if(pass_counts[i] == OPT_FILTER_TEST_COUNT) {
			// pull the candidate instructions
			inst survivor_inst[OPT_PROGRAM_LEN];
			dtoh_memcpy(survivor_inst, p + i, sizeof(opt_program));
			const f64 t0_smt = get_time_ms();
			program survivor = {survivor_inst, len};
			// verify via an SMT solver
			smt::result res = smt::equiv(prog, survivor, live_out);
			ms_smt += get_time_ms() - t0_smt;
			++smt_calls;

			if(res.kind == smt::result::EQUIVALENT) {
				// equivalent program
				inst* dst = mem.push<inst>(len);
				memcpy(dst, survivor_inst, sizeof(inst) * len);
				best = {dst, len};
				return true;
			} else if(res.kind == smt::result::COUNTEREXAMPLE) {
				// add the counterexample (round robin), then abort this batch
				const u32 slot = 16 + (counterexample_count % 16);
				counterexample_count++;
				test_in[slot] = res.counterexample;
				target_out[slot] = opt_host_run(prog, &res.counterexample);
				return false;
			}
		}
	}

	return false;
}

void optimizer::log_startup() {
	arena scratch;

	printf("source (len: %zu):\n", prog.size);
	string src = prog.to_string(scratch);
	printf("%s", (const c8*)src.ptr);
	printf("live-in:  { ");
	opt_print_reg_mask(live_in);
	printf(" }\n");
	printf("live-out: { ");
	opt_print_reg_mask(live_out);
	printf(" }\n");
	u32 effective_mask = opt.ext_mask | EXT_RV32I;
	if(effective_mask & EXT_RV64M) effective_mask |= EXT_RV32M;
	printf("extensions: ");
	print_enabled_extensions(effective_mask);
	printf("\n");
	printf("max prog len: %u\n", OPT_PROGRAM_LEN);
	printf("batch size: %zu cands\n", opt.batch_size);
}

void optimizer::log_results(b32 found) {
	if(!found) {
		printf("done: no optimizations found (len: %u)\n", OPT_PROGRAM_LEN);
		return;
	}

	printf("done: optimization found (len: %zu):\n", best.size);
	string s = best.to_string(mem);
	printf("%s", (const c8*)s.ptr);
}

void optimizer::log_stats() {
	printf("statistics:\n");
	printf("  candidates:  %.2fM\n", (f64)total_candidates / 1e6);
	const f64 safe_ms_enum = (ms_enum > 0.0) ? ms_enum : 0.001;
	const f64 eps = (f64)total_candidates / (safe_ms_enum / 1000.0);
	const f64 epsm = eps / 1e6;
	printf("  enum time:   %.2fms (%.2fM cand/sec)\n", ms_enum, epsm);
	const f64 safe_ms_filter = (ms_filter > 0.0) ? ms_filter : 0.001;
	const f64 fps = (f64)total_candidates / (safe_ms_filter / 1000.0);
	const f64 fpsm = fps / 1e6;
	printf("  filter time: %.2fms (%.2fM cand/sec)\n", ms_filter, fpsm);
	printf("  smt time:    %.2fms (%zu calls)\n", ms_smt, smt_calls);
	printf("  total time:  %.2fms\n", ms_total);
}

void optimizer::init_tests() {
	// 32 random test vectors at start, the CEGIS loop adds counterexamples, which
	// are placed into the last 16 slots (round robin)
	u64 s = opt.seed ^ 0x9E3779B97F4A7C15ull;

	for(u32 t = 0; t < OPT_FILTER_TEST_COUNT; ++t) {
		cpu_state in = {};

		for(u32 i = 0; i < 32; ++i) {
			s ^= s >> 30;
			s *= 0xBF58476D1CE4E5B9ull;
			s ^= s >> 27;
			s *= 0x94D049BB133111EBull;
			s ^= s >> 31;
			in.regs[i] = s;
		}

		in.regs[0] = 0; // x0 invariant
		test_in[t] = in;
		target_out[t] = opt_host_run(prog, &in);
	}
}
} // namespace sup