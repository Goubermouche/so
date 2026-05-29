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
	optimizer->cur_max_scratch = 0;
	optimizer->cur_active_mask = 0;
	optimizer->cur_n_meta = 0;
	optimizer->cur_imms = {};
	optimizer->counterexample_count = 0;
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
	U32 prev_cex = optimizer->counterexample_count;

	// generate candidates
	F64 t_upper = get_time_ms();
	enum_run(&optimizer->enumerate, cfg);
	optimizer->ms_enum += get_time_ms() - t_upper;

	// pull and filter chunks until the saved last-layer frontier is exhausted,
	// or a solution / new counterexample is found
	U64 total_emitted = 0;
	for(;;) {
		F64 t_chunk = get_time_ms();
		U64 emitted = enum_emit_batch(&optimizer->enumerate);
		optimizer->ms_enum += get_time_ms() - t_chunk;

		if(emitted == 0) { break; }
		total_emitted += emitted;

		B32 found = optimizer_filter_batch(optimizer, len);
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
	enum_make_meta_host(&opcodes, optimizer->cur_meta, &optimizer->cur_n_meta);
	optimizer->cur_imms = immediates;
	filter_upload_meta(optimizer->cur_meta, optimizer->cur_n_meta, immediates.vals, immediates.n);

	U32 max_scratch = Min(32, 5 + len);
	optimizer->cur_max_scratch = max_scratch;

	// compute the conservative active-register set for this pass, the enumerator only emits programs
	// that touch x0, registers 1..4 (low regs always considered as valid rd / scratch material), the
	// scratch range r in [5, max_scratch), and any register in live_in / live_out. this is the upper
	// bound on the regs the sim might see; the filter kernel uses it to size its packed reg file
	U64 scratch_mask = 0;
	U32 hi = max_scratch < 32 ? max_scratch : 32;
	for(U32 r = 5; r < hi; ++r) { scratch_mask |= 1ull << r; }
	U64 low_regs = 0x1Eull | 1ull; // bits 1..4 | x0
	optimizer->cur_active_mask =  low_regs | scratch_mask | optimizer->live_in | optimizer->live_out;

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

		I32 result = optimizer_run_iter(optimizer, &cfg, len, iter);
		if(result == 1) { return true; }
		if(result == -1) { return false; } // no new cex -> give up at this length
	}

	printf("    iter limit hit (len: %u)\n", len);
	return false;
}

void optimizer_reconstruct_survivor(Optimizer* optimizer, U64 i, U32 len, Instruction* out_inst) {
	Enum* e = &optimizer->enumerate;

	// fetch + decode the instruction for this cand
	PackedInstruction packed = 0;
	dtoh_memcpy(&packed, (PackedInstruction*)e->d_instructions + i, sizeof(PackedInstruction));
	UnpackedInstruction unpacked = instruction_unpack(packed);

	// pull parent code (slot-0 will be overwritten by the built instruction)
	EnumStateCode parent_code;
	EnumStateCode* d_parent_code = (EnumStateCode*)e->d_last_front_code + e->out_parent_base + unpacked.parent_local_id;
	dtoh_memcpy(&parent_code, d_parent_code, sizeof(EnumStateCode));

	// build slot-0 instruction from the packed instruction + meta + imm pool (host copies)
	EnumMeta& m = optimizer->cur_meta[unpacked.op_idx];
	out_inst[0] = enum_build_inst(&m, unpacked, optimizer->cur_imms.vals);
	for(U32 k = 1; k < len; ++k) { out_inst[k] = parent_code.code[k]; }
}

B32 optimizer_filter_batch(Optimizer* optimizer, U32 len) {
	Enum* e = &optimizer->enumerate;
	U64 p_cnt = e->out_n_cands;
	if(p_cnt == 0) { return false; }

	FilterOptions cfg;
	cfg.live_mask = optimizer->live_out;
	cfg.live_in_mask = optimizer->live_in;
	cfg.active_mask = optimizer->cur_active_mask;
	cfg.prog_len = len;
	cfg.instructions = (PackedInstruction*)e->d_instructions;
	cfg.parent_code = (EnumStateCode*)e->d_last_front_code + e->out_parent_base;
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
	// via an SMT solver
	for(U64 i = 0; i < p_cnt; ++i) {
		if(pass_counts[i] == FilterTestCount) {
			Instruction survivor_inst[MaxProgramLen];
			optimizer_reconstruct_survivor(optimizer, i, len, survivor_inst);
			F64 t0_smt = get_time_ms();
			Program survivor = {survivor_inst, len};
			// verify via an SMT solver
			SMT_Result res = smt_equiv(optimizer->prog, &survivor, optimizer->live_out);
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
				U32 slot = 16 + (optimizer->counterexample_count % 16);
				optimizer->counterexample_count++;
				optimizer->test_in[slot] = res.counterexample;
				optimizer->target_out[slot] = ext_run_program(optimizer->prog, &res.counterexample);
				optimizer->filter.tests_dirty = true; // test set changed, mark dirty
				return false;
			}
		}
	}

	return false;
}

void optimizer_log_startup(Optimizer* optimizer) {
	Arena* scratch = arena_make(0);

	printf("source (len: %u):\n", optimizer->prog->size);
	S8 src = program_to_string(optimizer->prog, scratch);
	printf("%s", (C8*)src.ptr);
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
	S8 s = program_to_string(&optimizer->best, optimizer->mem);
	printf("%s", (C8*)s.ptr);
}

void optimizer_log_stats(Optimizer* optimizer) {
	printf("statistics:\n");
	printf("  candidates:  %.2fM\n", (F64)optimizer->total_candidates / 1e6);
	F64 safe_ms_enum = (optimizer->ms_enum > 0.0) ? optimizer->ms_enum : 0.001;
	F64 eps = (F64)optimizer->total_candidates / (safe_ms_enum / 1000.0);
	F64 epsm = eps / 1e6;
	printf("  enum time:   %.2fms (%.2fM cand/sec)\n", optimizer->ms_enum, epsm);
	F64 safe_ms_filter = (optimizer->ms_filter > 0.0) ? optimizer->ms_filter : 0.001;
	F64 fps = (F64)optimizer->total_candidates / (safe_ms_filter / 1000.0);
	F64 fpsm = fps / 1e6;
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
		optimizer->target_out[t] = ext_run_program(optimizer->prog, &in);
	}

	optimizer->filter.tests_dirty = true; // new tests, mark dirty
}