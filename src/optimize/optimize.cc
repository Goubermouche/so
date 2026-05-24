#include "optimize/optimize.h"
#include "cpu/instruction.cuh"
#include "cpu/program.h"
#include "optimize/enumerate.cuh"
#include "optimize/filter.cuh"
#include "smt/smt.h"
#include "util/arena.h"
#include "util/type.h"

void optimizer_make_default_options(OptimizerOptions* opt) {
	opt->seed = 1;
	opt->ext_mask = ExtRV32I;
	opt->batch_size = 4000000;
	opt->max_cegis_iters = 8;
}

I32 optimizer_make(Optimizer* optimizer, OptimizerOptions* opt) {
	optimizer->opt = opt;
	optimizer->total_candidates = 0;
	optimizer->filter_passes = 0;
	optimizer->smt_calls = 0;
	optimizer->ms_enum = 0.0;
	optimizer->ms_filter = 0.0;
	optimizer->ms_smt = 0.0;
	optimizer->ms_total = 0.0;
	optimizer->mem = arena_make(0);

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
	arena_free(optimizer->mem);
}

I32 optimizer_run(Optimizer* optimizer, Program* program) {
	if(program->size > MaxProgramLen) {
		fprintf(stderr, "error: optimizer_run: max program size (%d) exceeded", MaxProgramLen);
		return 1;
	}

	optimizer->prog = program;
	optimizer->live_out = program_get_live_out(program);
	optimizer->live_in = program_get_live_in(program);

	optimizer_log_startup(optimizer);
	optimizer_init_tests(optimizer);
	printf("begin search\n");

	F64 t0 = get_time_ms();
	B32 found = false;

	for(U32 len = 1; len <= MaxProgramLen; ++len) {
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

I32 optimizer_run_iter(Optimizer* optimizer, EnumOptions* cfg, U32 len, U32 iter) {
	const U32 prev_cex = optimizer->counterexample_count;

	// generate candidates
	const F64 t_upper = get_time_ms();
	enum_run(&optimizer->enumerate, cfg);
	optimizer->ms_enum += get_time_ms() - t_upper;

	// pull and filter chunks until the saved last-layer frontier is exhausted,
	// or a solution / new counterexample is found
	U64 total_emitted = 0;
	for(;;) {
		const F64 t_chunk = get_time_ms();
		U64 emitted = enum_emit_batch(&optimizer->enumerate);
		optimizer->ms_enum += get_time_ms() - t_chunk;

		if(emitted == 0) { break; }
		total_emitted += emitted;

		EnumProgram* p = optimizer->enumerate.out_d_cands;
		B32 found = optimizer_filter_batch(optimizer, p, emitted, len);
		if(found) {
			printf("    iter %u (%.2fM cand)\n", iter + 1, (F64)total_emitted / 1e6);
			return 1;
		}

		// if a new cex was added, abort this iter so the next one re-enumerates with the tighter filter
		if(optimizer->counterexample_count != prev_cex) { break; }
	}

	printf("    iter %u (%.2fM cand)\n", iter + 1, (F64)total_emitted / 1e6);
	return optimizer->counterexample_count != prev_cex ? 0 : -1;
}

B32 optimizer_run_length(Optimizer* optimizer, U32 len) {
	U32 effective_mask = optimizer->opt->ext_mask | ExtRV32I;
	if(effective_mask & ExtRV64M) effective_mask |= ExtRV32M;

	EnumOpcodePool opcodes;
	EnumImmPool immediates;
	enum_make_opcode_pool(&opcodes, effective_mask);
	enum_make_imm_pool(&immediates, optimizer->prog);

	U32 max_scratch = Min(32, 5 + len);

	// CEGIS main loop for instructions of length 'len'. iterates until we
	// either find a satisfactory program (SMT-proven equivalence), or until
	// we don't find any new counterexamples in a full pass.
	for(U32 iter = 0; iter < optimizer->opt->max_cegis_iters; ++iter) {
		EnumOptions cfg;
		cfg.pool = &opcodes;
		cfg.imms = &immediates;
		cfg.live_in_mask = optimizer->live_in;
		cfg.live_out_mask = optimizer->live_out;
		cfg.prog_len = len;
		cfg.max_scratch = max_scratch;
		cfg.cap = optimizer->opt->batch_size;

		const I32 result = optimizer_run_iter(optimizer, &cfg, len, iter);
		if(result == 1) { return true; }
		if(result == -1) { return false; } // no new cex -> give up at this length
	}

	printf("    iter limit hit (len: %u)\n", len);
	return false;
}

B32 optimizer_filter_batch(Optimizer* optimizer, EnumProgram* p, U64 p_cnt, U32 len) {
	if(p_cnt == 0) { return false; }
	FilterOptions cfg;
	cfg.live_mask = optimizer->live_out;
	cfg.prog_len = len;
	cfg.candidates = (Instruction*)p;
	cfg.n_candidates = p_cnt;
	cfg.test_in = optimizer->test_in;
	cfg.target_out = optimizer->target_out;

	// run mass filter - remove the majority of candidate programs by verifying
	// their correctness against a set of random and counterexample tests
	U8* pass_counts = 0;
	F64 t0_filter = get_time_ms();
	filter_run(&optimizer->filter, &cfg, &pass_counts);
	optimizer->ms_filter += get_time_ms() - t0_filter;
	optimizer->total_candidates += p_cnt;
	optimizer->filter_passes++;

	// go through our candidates, if they passed the test set we verify them
	// via an SMT_State solver
	for(U64 i = 0; i < p_cnt; ++i) {
		if(pass_counts[i] == FilterTestCount) {
			// pull the candidate instructions
			Instruction survivor_inst[MaxProgramLen];
			dtoh_memcpy(survivor_inst, p + i, sizeof(EnumProgram));
			const F64 t0_smt = get_time_ms();
			Program survivor = {survivor_inst, len};
			// verify via an SMT_State solver
			SMT_Result res = smt_equiv(*optimizer->prog, survivor, optimizer->live_out);
			optimizer->ms_smt += get_time_ms() - t0_smt;
			++optimizer->smt_calls;

			if(res.type == SMT_ResultType_EQUIVALENT) {
				// equivalent Program
				Instruction* dst = ArenaPush(optimizer->mem, Instruction, len);
				memcpy(dst, survivor_inst, sizeof(Instruction) * len);
				optimizer->best = {dst, len};
				return true;
			} else if(res.type == SMT_ResultType_COUNTEREXAMPLE) {
				// add the counterexample (round robin), then abort this batch.
				// mark tests dirty so the next filter_run re-uploads them
				const U32 slot = 16 + (optimizer->counterexample_count % 16);
				optimizer->counterexample_count++;
				optimizer->test_in[slot] = res.counterexample;
				optimizer->target_out[slot] = filter_run_host(optimizer->prog, &res.counterexample);
				filter_mark_tests_dirty(&optimizer->filter);
				return false;
			}
		}
	}

	return false;
}

void optimizer_log_startup(Optimizer* optimizer) {
	Arena* scratch = arena_make(0);

	printf("source (len: %u):\n", optimizer->prog->size);
	Str src = program_to_string(optimizer->prog, scratch);
	printf("%s", (const C8*)src.ptr);
	printf("live-in:  { ");
	opt_print_reg_mask(optimizer->live_in);
	printf(" }\n");
	printf("live-out: { ");
	opt_print_reg_mask(optimizer->live_out);
	printf(" }\n");
	U32 effective_mask = optimizer->opt->ext_mask | ExtRV32I;
	if(effective_mask & ExtRV64M) effective_mask |= ExtRV32M;
	printf("extensions: ");
	B32 first = true;
	for(U32 i = 0; i < DatabaseExtensionCount; ++i) {
		if(effective_mask & DatabaseExtensionBits[i]) {
			printf("%s%s", first ? "" : ", ", DatabaseExtensionNames[i].ptr);
			first = false;
		}
	}
	printf("\n");
	printf("max prog len: %u\n", MaxProgramLen);
	printf("batch size: %zu cands\n", optimizer->opt->batch_size);
	arena_free(scratch);
}

void optimizer_log_results(Optimizer* optimizer, B32 found) {
	if(!found) {
		printf("done: no optimizations found (len: %u)\n", MaxProgramLen);
		return;
	}

	printf("done: optimization found (len: %u):\n", optimizer->best.size);
	Str s = program_to_string(&optimizer->best, optimizer->mem);
	printf("%s", (const C8*)s.ptr);
}

void optimizer_log_stats(Optimizer* optimizer) {
	printf("statistics:\n");
	printf("  candidates:  %.2fM\n", (F64)optimizer->total_candidates / 1e6);
	const F64 safe_ms_enum = (optimizer->ms_enum > 0.0) ? optimizer->ms_enum : 0.001;
	const F64 eps = (F64)optimizer->total_candidates / (safe_ms_enum / 1000.0);
	const F64 epsm = eps / 1e6;
	printf("  enum time:   %.2fms (%.2fM cand/sec)\n", optimizer->ms_enum, epsm);
	const F64 safe_ms_filter = (optimizer->ms_filter > 0.0) ? optimizer->ms_filter : 0.001;
	const F64 fps = (F64)optimizer->total_candidates / (safe_ms_filter / 1000.0);
	const F64 fpsm = fps / 1e6;
	printf("  filter time: %.2fms (%.2fM cand/sec)\n", optimizer->ms_filter, fpsm);
	printf("  smt time:    %.2fms (%zu calls)\n", optimizer->ms_smt, optimizer->smt_calls);
	printf("  total time:  %.2fms\n", optimizer->ms_total);
}

void optimizer_init_tests(Optimizer* optimizer) {
	// 32 random test vectors at start, the CEGIS loop adds counterexamples, which
	// are placed into the last 16 slots (round robin)
	U64 s = optimizer->opt->seed ^ 0x9E3779B97F4A7C15ull;

	for(U32 t = 0; t < FilterTestCount; ++t) {
		CpuState in = {};

		for(U32 i = 0; i < 32; ++i) {
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

	filter_mark_tests_dirty(&optimizer->filter);
}