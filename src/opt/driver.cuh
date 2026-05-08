#ifndef DRIVER_CUH
#define DRIVER_CUH

#include "int/cpu.cuh"
#include "int/instruction.cuh"

namespace sup {
	static constexpr u32 SYNTH_PROG_LEN = 8;
	static constexpr u32 SYNTH_N_TESTS = 64;
	static constexpr u32 N_WARPS_PER_BLOCK = 4;
	static constexpr u32 THREADS_PER_BLOCK = N_WARPS_PER_BLOCK * 32;

	struct synth_config {
		u64 live_mask;
		u32 n_tests;
		u32 prog_len;
	};

	struct synth_result {
		u32 fail_mask;
		u32 pass_count;
	};

	struct gpu_runner {
		gpu_runner();
		~gpu_runner();

		i32 init(u64 requested_max_chunk_cands = 0);
		u64 chunk_size() const { return m_max_chunk_cands; }

		void run(
			const inst* candidates,
			u64 n_candidates,
			const cpu_state* test_in,
			const cpu_state* target_out,
			const synth_config& cfg,
			synth_result* results,
			f64* elapsed_ms_total);

	private:
		u64 m_max_chunk_cands;
		void* m_d_cands;
		void* m_d_test_in;
		void* m_d_target_out;
		void* m_d_fail_mask;
		void* m_d_pass_count;
		void* m_h_fail_mask;
		void* m_h_pass_count;
	};
} // namespace sup

#endif // #ifndef DRIVER_CUH

