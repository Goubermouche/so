#include "opt/optimize.h"
#include "cpu/instruction.cuh"
#include "cpu/program.h"
#include "opt/batch_runner.cuh"
#include "opt/canon.cuh"
#include "opt/driver.cuh"

opt_config opt_make_default_config() {
	opt_config cfg;
	cfg.live_mask = 0;
	cfg.seed = 1;
	cfg.ext_mask = EXT_RV32I;
	cfg.max_prog_len = 6;
	cfg.batch_size = 4000000;
	cfg.gpu_chunk_size = 0;
	cfg.max_cegis_iters = 8;
	return cfg;
}

void opt_log_startup(const opt_context* ctx) {
	arena scratch = arena_make(0);

	printf("> source (%u instructions):\n", ctx->prog->size);
	str src = cpu_program_to_str(&scratch, ctx->prog);
	printf("%s", (const char*)src.str);
	printf("> live-in:  { ");
	opt_print_reg_mask(ctx->live_in);
	printf(" }\n");
	printf("> live-out: { ");
	opt_print_reg_mask(ctx->live_out);
	printf(" }\n");

	// extensions
	u32 effective_mask = ctx->cfg->ext_mask | EXT_RV32I;
	if(effective_mask & EXT_RV64M) effective_mask |= EXT_RV32M;
	printf("> extensions: ");
	cpu_print_enabled_extensions(effective_mask);
	printf("\n");

	printf("> max prog len: %u\n", ctx->cfg->max_prog_len);
	printf("> batch size: %zu\n", ctx->cfg->batch_size);

	arena_release(&scratch);
}

void opt_log_results(const opt_context* ctx, b32 found) {
	printf("> finished\n");
	printf("  total candidates evaluated: %zu\n", ctx->total_candidates);
	printf("  total gpu time: %fms\n", ctx->total_gpu_ms);
	printf("  total smt time: %fms (%zu calls)\n", ctx->total_smt_ms, ctx->total_smt_calls);

	if(ctx->total_gpu_ms > 0) {
		const f64 cps = (f64)ctx->total_candidates / (ctx->total_gpu_ms / 1000.0);
		printf("  gpu throughput: %fM cand/sec\n", cps / 1e6);
	}

	if(found) {
		cpu_program live_prog;
		live_prog.size = ctx->best_prog_len;
		live_prog.instructions = (cpu_inst*)malloc(sizeof(cpu_inst) * live_prog.size);
		memcpy(live_prog.instructions, ctx->best_prog, sizeof(cpu_inst) * live_prog.size);
		printf("> best program (%u instructions, SMT VERIFIED equivalent):\n", ctx->best_len);
		arena scratch = arena_make(0);
		str s = cpu_program_to_str(&scratch, &live_prog);
		printf("%s", (const char*)s.str);
		arena_release(&scratch);
		cpu_program_free(&live_prog);
	} else {
		printf("> no equivalent program found within length %u\n", ctx->cfg->max_prog_len);
	}
}

void opt_print_reg_mask(u64 mask) {
	b32 first = true;

	for(u32 r = 0; r < 32; ++r) {
		if(mask & (1ULL << r)) {
			printf("%s%s", first ? "" : ",", cpu_reg_name(r));
			first = false;
		}
	}

	if(first) { printf("(none)"); }
}

void opt_seed_test_vectors(opt_context* ctx) {
	// 32 random test vectors at start, the CEGIS loop adds counterexamples in subsequent slots
	const u32 n_initial = 32;
	u64 s = ctx->cfg->seed ^ 0x9E3779B97F4A7C15ULL;

	for(u32 t = 0; t < n_initial; ++t) {
		cpu_state in = {};

		for(u32 i = 0; i < 32; ++i) {
			s ^= s >> 30;
			s *= 0xBF58476D1CE4E5B9ULL;
			s ^= s >> 27;
			s *= 0x94D049BB133111EBULL;
			s ^= s >> 31;
			in.regs[i] = s;
		}

		in.regs[0] = 0; // x0 invariant
		ctx->test_in[t] = in;
		ctx->target_out[t] = opt_host_run(ctx->prog, &in);
	}

	ctx->n_tests = n_initial;
}

void opt_filter_batch(opt_context* ctx, const opt_candidate_arr* cands) {
	const u64 N = cands->size;
	if(N == 0) { return; }

	arena scratch = arena_make(0);
	cpu_inst* flat = push_array(&scratch, cpu_inst, N * SYNTH_PROG_LEN);

	for(u64 i = 0; i < N; ++i) {
		const opt_candidate& c = cands->v[i];

		for(u32 j = 0; j < SYNTH_PROG_LEN; ++j) {
			if(j < c.len) {
				flat[i * SYNTH_PROG_LEN + j] = c.code[j];
			} else {
				cpu_inst nop = {};
				nop.op = OP_NOP;
				flat[i * SYNTH_PROG_LEN + j] = nop;
			}
		}
	}

	opt_synth_config gcfg;
	gcfg.live_mask = ctx->live_out;
	gcfg.n_tests = ctx->n_tests;
	gcfg.prog_len = cands->v[0].len;
	gcfg.candidates = flat;
	gcfg.n_candidates = N;
	gcfg.test_in = ctx->test_in;
	gcfg.target_out = ctx->target_out;
	opt_synth_result* results = push_array(&scratch, opt_synth_result, N);
	opt_gpu_runner_run(&ctx->gpu, &gcfg, results);
	ctx->total_gpu_ms += gcfg.elapsed_ms_total;
	ctx->total_candidates += N;
	++ctx->total_gpu_passes;

	// any candidate that passed all tests is forwarded to SMT
	u64 ok_count = 0;
	for(u64 i = 0; i < N; ++i) {
		if(results[i].pass_count == ctx->n_tests) {
			++ok_count;
			// SMT verify
			cpu_inst* rw = flat + i * SYNTH_PROG_LEN;
			const u32 rw_len = cands->v[i].len;
			const f64 t0 = get_time_ms();
			cpu_program b = {rw, rw_len};
			smt_verify_report rep = smt_eq(ctx->prog, &b, ctx->live_out);
			ctx->total_smt_ms += get_time_ms() - t0;
			++ctx->total_smt_calls;

			if(rep.kind == SMT_EQUIVALENT) {
				ctx->rep = rep;
				// copy the winning program before we release the scratch arena
				cpu_inst* dst = push_array(&ctx->mem, cpu_inst, rw_len);
				memcpy(dst, rw, sizeof(cpu_inst) * rw_len);
				ctx->best_prog = dst;
				ctx->best_prog_len = rw_len;
				arena_release(&scratch);
				return;
			} else if(rep.kind == SMT_COUNTEREXAMPLE) {
				// add the counterexample, then abort this batch
				if(ctx->n_tests < SYNTH_N_TESTS) {
					const u32 slot = ctx->n_tests++;
					ctx->test_in[slot] = rep.counterexample;
					ctx->target_out[slot] = opt_host_run(ctx->prog, &rep.counterexample);
				}

				arena_release(&scratch);
				return;
			}
		}
	}

	arena_release(&scratch);
}

void opt_run(const cpu_program* prog, const opt_config* cfg) {
	opt_context ctx;
	ctx.n_tests = 0;
	ctx.best_len = 0;
	ctx.best_prog = 0;
	ctx.best_prog_len = 0;
	ctx.total_candidates = 0;
	ctx.total_gpu_passes = 0;
	ctx.total_gpu_ms = 0.0;
	ctx.total_smt_ms = 0.0;
	ctx.total_smt_calls = 0;
	ctx.prog = prog;
	ctx.cfg = cfg;
	ctx.live_out = cfg->live_mask ? cfg->live_mask : cpu_program_live_outs(prog);
	ctx.live_in = opt_compute_live_in(prog->instructions, prog->size);
	ctx.mem = arena_make(0);

	opt_log_startup(&ctx);
	opt_seed_test_vectors(&ctx);
	if(opt_gpu_runner_make(&ctx.gpu, ctx.cfg->gpu_chunk_size)) {
		fprintf(stderr, "error: gpu_runner::init failed\n");
		arena_release(&ctx.mem);
		return;
	}

	b32 found = false;
	for(u32 L = 1; L <= ctx.cfg->max_prog_len; ++L) {
		printf("> searching length %u\n", L);
		if(opt_run_length(&ctx, L)) {
			found = true;
			ctx.best_len = L;
			break;
		}
	}

	opt_log_results(&ctx, found);
	arena_release(&ctx.mem);
}

b32 opt_run_length(opt_context* ctx, u32 len) {
	u32 effective_mask = ctx->cfg->ext_mask | EXT_RV32I;
	if(effective_mask & EXT_RV64M) effective_mask |= EXT_RV32M;

	const opt_opcode_pool pool = opt_build_opcode_pool(effective_mask);
	const opt_imm_pool imms = opt_build_default_imm_pool(); // TODO: add imms from programm etc.
	u32 max_scratch = 5 + len;
	if(max_scratch > 32) max_scratch = 32;

	// regenerate candidates if the test set grows
	u32 cegis_iter = 0;

	while(cegis_iter < ctx->cfg->max_cegis_iters) {
		const u32 prev_n_tests = ctx->n_tests;
		arena iter_arena = arena_make(0);
		opt_candidate_arr cands = opt_candidate_arr_make(&iter_arena);
		opt_candidate_arr_reserve(&cands, ctx->cfg->batch_size);

		const f64 t0 = get_time_ms();
		opt_enum_config cfg = {&pool, &imms, ctx->live_in, ctx->live_out, len, max_scratch};
		opt_enumerate(&cfg, &cands, ctx->cfg->batch_size);

		printf("  iter %u (%zu candidates (%fms))\n", cegis_iter, cands.size, get_time_ms() - t0);
		if(cands.size == 0) {
			arena_release(&iter_arena);
			return false;
		}

		opt_filter_batch(ctx, &cands);

		if(ctx->best_prog != 0) {
			arena_release(&iter_arena);
			return true;
		}

		// if no new counterexample was added, we exhausted the candidate space at this L without
		// finding equivalence
		if(ctx->n_tests == prev_n_tests) {
			arena_release(&iter_arena);
			return false;
		}

		arena_release(&iter_arena);
		++cegis_iter;
	}

	printf("  iter limit hit at length %u\n", len);
	return false;
}
