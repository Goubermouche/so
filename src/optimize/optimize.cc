#include "optimize/optimize.h"
#include "cpu/instruction.cuh"
#include "cpu/program.h"
#include "optimize/batch_runner.cuh"
#include "optimize/canon.cuh"
#include "optimize/filter.cuh"
#include "util/type.h"

opt_cfg opt_cfg_make_default() {
	opt_cfg cfg;
	cfg.seed = 1;
	cfg.ext_mask = EXT_RV32I;
	cfg.batch_size = 4000000;
	cfg.max_cegis_iters = 8;
	return cfg;
}

void opt_log_startup(const opt_ctx* ctx) {
	arena scratch = arena_make(0);

	printf("source (len: %u):\n", ctx->prog->size);
	str src = cpu_program_to_str(&scratch, ctx->prog);
	printf("%s", (const char*)src.str);
	printf("live-in:  { ");
	opt_print_reg_mask(ctx->live_in);
	printf(" }\n");
	printf("live-out: { ");
	opt_print_reg_mask(ctx->live_out);
	printf(" }\n");
	u32 effective_mask = ctx->cfg->ext_mask | EXT_RV32I;
	if(effective_mask & EXT_RV64M) effective_mask |= EXT_RV32M;
	printf("extensions: ");
	cpu_print_enabled_extensions(effective_mask);
	printf("\n");
	printf("max prog len: %u\n", OPT_PROGRAM_LEN);
	printf("batch size: %zu cands\n", ctx->cfg->batch_size);

	arena_release(&scratch);
}

void opt_log_results(opt_ctx* ctx, b32 found) {
	if(!found) {
		printf("done: no optimizations found (len: %u)\n", OPT_PROGRAM_LEN);
		return;
	}

	printf("done: optimization found (len: %u):\n", ctx->best.size);
	str s = cpu_program_to_str(&ctx->mem, &ctx->best);
	printf("%s", (const char*)s.str);
}

void opt_log_stats(const opt_ctx* ctx) {
	printf("statistics:\n");
	printf("  candidates:  %.2fM\n", (f64)ctx->total_candidates / 1e6);
	const f64 eps = (f64)ctx->total_candidates / (ctx->ms_enum / 1000.0);
	const f64 epsm = eps / 1e6;
	printf("  enum time:   %.2fms (%.2fM cand/sec)\n", ctx->ms_enum, epsm);
	const f64 fps = (f64)ctx->total_candidates / (ctx->ms_filter / 1000.0);
	const f64 fpsm = fps / 1e6;
	printf("  filter time: %.2fms (%.2fM cand/sec)\n", ctx->ms_filter, fpsm);
	printf("  smt time:    %.2fms (%zu calls)\n", ctx->ms_smt, ctx->smt_calls);
	printf("  total time:  %.2fms\n", ctx->ms_total);
}

void opt_print_reg_mask(u64 mask) {
	b32 first = true;

	for(u32 r = 0; r < 32; ++r) {
		if(mask & (1ull << r)) {
			printf("%s%s", first ? "" : ",", cpu_reg_name(r));
			first = false;
		}
	}

	if(first) { printf("(none)"); }
}

void opt_init_tests(opt_ctx* ctx) {
	// 32 random test vectors at start, the CEGIS loop adds counterexamples, which
	// are placed into the last 16 slots (round robin)
	u64 s = ctx->cfg->seed ^ 0x9E3779B97F4A7C15ull;

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
		ctx->test_in[t] = in;
		ctx->target_out[t] = opt_host_run(ctx->prog, &in);
	}
}

b32 opt_filter_batch(opt_ctx* ctx, const opt_program* p, u64 p_cnt, u32 len) {
	if(p_cnt == 0) { return false; }
	arena scratch = arena_make(0);
	opt_filter_cfg cfg;
	cfg.live_mask = ctx->live_out;
	cfg.prog_len = len;
	cfg.candidates = (const cpu_inst*)p;
	cfg.n_candidates = p_cnt;
	cfg.test_in = ctx->test_in;
	cfg.target_out = ctx->target_out;
	u8* pass_counts = PUSH_ARRAY(&scratch, u8, p_cnt);

	// run mass filter - remove the majority of candidate programs by verifying
	// their correctness against a set of random and counterexample tests
	f64 t0_filter = get_time_ms();
	opt_filter_run(&ctx->filter, &cfg, pass_counts);
	ctx->ms_filter += get_time_ms() - t0_filter;
	ctx->total_candidates += p_cnt;
	ctx->filter_passes++;

	// go through our candidates, if they passed the test set we verify them
	// via an SMT solver
	for(u64 i = 0; i < p_cnt; ++i) {
		if(pass_counts[i] == OPT_FILTER_TEST_COUNT) {
			// pull the candidate instructions
			cpu_inst survivor_inst[OPT_PROGRAM_LEN];
			dtoh_memcpy(survivor_inst, p + i, sizeof(opt_program));
			const f64 t0_smt = get_time_ms();
			cpu_program survivor = {survivor_inst, len};
			// verify via an SMT solver
			smt_result res = smt_eq(ctx->prog, &survivor, ctx->live_out);
			ctx->ms_smt += get_time_ms() - t0_smt;
			++ctx->smt_calls;

			if(res.kind == SMT_EQUIVALENT) {
				// equivalent program
				cpu_inst* dst = PUSH_ARRAY(&ctx->mem, cpu_inst, len);
				memcpy(dst, survivor_inst, sizeof(cpu_inst) * len);
				ctx->best = { dst, len };
				arena_release(&scratch);
				return true;
			} else if(res.kind == SMT_COUNTEREXAMPLE) {
				// add the counterexample (round robin), then abort this batch
				const u32 slot = 16 + (ctx->counterexample_count % 16);
				ctx->counterexample_count++;
				ctx->test_in[slot] = res.counterexample;
				ctx->target_out[slot] = opt_host_run(ctx->prog, &res.counterexample);
				arena_release(&scratch);
				return false;
			}
		}
	}

	arena_release(&scratch);
	return false;
}

b32 opt_run_length(opt_ctx* ctx, u32 len) {
	u32 effective_mask = ctx->cfg->ext_mask | EXT_RV32I;
	if(effective_mask & EXT_RV64M) effective_mask |= EXT_RV32M;

	const opt_opcode_pool opcodes = opt_build_opcode_pool(effective_mask);
	const opt_imm_pool immediates = opt_build_imm_pool();

	u32 max_scratch = MIN(32, 5 + len);
	u32 iter = 0;

	// CEGIS main loop for instructions of length 'len', iterates until we either
	// find a satisfactory program (SMT proven equivalence), or until we don't
	// find any new counterexammples
	while(iter < ctx->cfg->max_cegis_iters) {
		const u32 prev_counterexample_count = ctx->counterexample_count;
		const f64 t0 = get_time_ms();
		opt_enum_cfg cfg;
		cfg.pool = &opcodes;
		cfg.imms = &immediates;
		cfg.live_in_mask = ctx->live_in;
		cfg.live_out_mask = ctx->live_out;
		cfg.prog_len = len;
		cfg.max_scratch = max_scratch;
		opt_program* p = nullptr;
		u64 p_cnt = 0;

		// generate candidates
		opt_enumerate(&ctx->enumerate, &cfg, ctx->cfg->batch_size, &p, &p_cnt);
		ctx->ms_enum += get_time_ms() - t0;
		printf("    iter %u (%.2fM cand)\n", iter + 1, (f64)p_cnt / 1e6);

		if(p_cnt == 0) { return false; }
		// filter candidates,
		b32 found_solution = opt_filter_batch(ctx, p, p_cnt, len);
		if(found_solution) { return true; }
		// exit if we run out of new counterexamples
		if(ctx->counterexample_count == prev_counterexample_count) { return false; }
		++iter;
	}

	printf("    iter limit hit (len: %u)\n", len);
	return false;
}

void opt_run(const cpu_program* prog, const opt_cfg* cfg) {
	f64 t0 = get_time_ms();
	opt_ctx ctx = {0};
	ctx.prog = prog;
	ctx.cfg = cfg;
	ctx.live_out = cpu_program_live_outs(prog);
	ctx.live_in = opt_compute_live_in(prog->instructions, prog->size);
	ctx.mem = arena_make(0);

	opt_log_startup(&ctx);
	opt_init_tests(&ctx);
	const u64 chunk_cap = ctx.cfg->batch_size;

	if(opt_filter_make(&ctx.filter, chunk_cap)) {
		fprintf(stderr, "error: filter::init failed\n");
		arena_release(&ctx.mem);
		return;
	}

	if(opt_enum_make(&ctx.enumerate, ctx.cfg->batch_size)) {
		fprintf(stderr, "error: enum_ctx::init failed\n");
		opt_filter_free(&ctx.filter);
		arena_release(&ctx.mem);
		return;
	}

	printf("begin search\n");
	b32 found = false;
	for(u32 len = 1; len <= OPT_PROGRAM_LEN; ++len) {
		printf("  searching length %u\n", len);
		if(opt_run_length(&ctx, len)) {
			found = true;
			break;
		}
	}

	ctx.ms_total = get_time_ms() - t0;
	opt_log_results(&ctx, found);
	opt_log_stats(&ctx);
	opt_enum_ctx_free(&ctx.enumerate);
	opt_filter_free(&ctx.filter);
	arena_release(&ctx.mem);
}