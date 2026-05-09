#ifndef OPTIMIZE_H
#define OPTIMIZE_H

#include "opt/driver.cuh"
#include "opt/enumerate.cuh"
#include "int/program.h"
#include "smt/smt.h"

namespace sup {
	struct config {
		u64 live_mask = 0;
		u64 seed = 1;
		u32 ext_mask = EXT_RV32I;
		u32 max_prog_len = 6;
		u64 batch_size = 4'000'000;
		u64 gpu_chunk_size = 0;
		u32 max_cegis_iters = 8;
	};

	void optimize(const str& prog, const config& cfg = {});
	void optimize(const program& prog, const config& cfg = {});

	namespace detail {
		struct optimizer {
			optimizer(const program& prog, const config& cfg);
			~optimizer();
			void run();
		private:
			void log_startup() const;
			void print_reg_mask(u64 mask) const;
			void seed_test_vectors();
			b32 run_length(u32 L);
			void filter_batch(const arr<candidate<SYNTH_PROG_LEN>>& cands);
			void log_results(b32 found) const;
		private:
			const program& m_prog;
			const config& m_cfg;
			u64 m_live_in;
			u64 m_live_out;
			cpu_state m_test_in[SYNTH_N_TESTS];
			cpu_state m_target_out[SYNTH_N_TESTS];
			u32 m_n_tests = 0;
			arr<inst> m_best_prog;
			u32 m_best_len = 0;
			smt_verify_report m_rep = {};
			// stats
			u64 m_total_candidates = 0;
			u64 m_total_gpu_passes = 0;
			f64 m_total_gpu_ms = 0.0;
			f64 m_total_smt_ms = 0.0;
			u64 m_total_smt_calls = 0;

			gpu_runner m_gpu;
		};
	} // namespace detail
} // namespace sup

#endif // #ifndef OPTIMIZE_H

