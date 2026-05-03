#ifndef BLOOM_CUH
#define BLOOM_CUH

#include "int/instruction.cuh"

namespace so {
	static constexpr u32 BLOOM_BLOCK_BITS  = 512;
	static constexpr u32 BLOOM_BLOCK_WORDS = BLOOM_BLOCK_BITS / 32; // 16
	static constexpr u32 BLOOM_K           = 7;

	SO_HD void inst_pack(const inst& in, u64 out[2]) {
		const inst_spec& spec = find_spec(in.op);
		u64 hdr = (u64)in.op;
		u64 imm = 0;

		for(u32 k = 0; k < 4; ++k) {
			const u8 shift = 16 + k * 8;

			if(spec.operands[k] == inst_spec::R64) {
				hdr |= ((u64)(u8)in.operands[k].reg & 0xFu) << shift;
			}
			else if(spec.operands[k] == inst_spec::I64) {
				imm = in.operands[k].i;
			}
		}

		out[0] = hdr;
		out[1] = imm;
	}

	SO_HD u64 hash_mix(u64 x) {
		x ^= x >> 33;
		x *= 0xFF51AFD7ED558CCDULL;
		x ^= x >> 33;
		x *= 0xC4CEB9FE1A85EC53ULL;
		x ^= x >> 33;
		return x;
	}

	SO_HD u64 hash_program64(const inst* prog, u32 n) {
		u64 h = 0xCBF29CE484222325ULL; // FNV offset basis

		for(u32 i = 0; i < n; ++i) {
			u64 packed[2];
			inst_pack(prog[i], packed);
			h ^= hash_mix(packed[0] + 0x9E3779B97F4A7C15ULL * (u64)(i + 1));
			h *= 0x100000001B3ULL; // FNV prime
			h ^= hash_mix(packed[1] + 0xBF58476D1CE4E5B9ULL * (u64)(i + 1));
			h *= 0x100000001B3ULL;
		}

		return hash_mix(h);
	}

#ifdef __CUDACC__
	__device__ inline b32 bloom_check_and_insert(u32* __restrict__ filter, u32 block_mask, u64 hash) {
		const u32 hash_hi = (u32)(hash >> 32);
		const u32 hash_lo = (u32)(hash);
		u32* block = filter + ((hash_hi & block_mask) * BLOOM_BLOCK_WORDS);
		u32 mix = hash_lo ? hash_lo : 0xdeadbeefu; // avoid zero LCG lock
		b32 all_set = true;

		#pragma unroll
		for(u32 k = 0; k < BLOOM_K; ++k) {
			mix = mix * 2654435761u + 0x9E3779B1u; // knuth multiplicative
			const u32 bit  = mix & (BLOOM_BLOCK_BITS - 1);
			const u32 word = bit >> 5;
			const u32 mask = 1u << (bit & 31);
			const u32 old  = atomicOr(&block[word], mask);

			if(!(old & mask)) {
				all_set = false;
			}
		}

		return all_set;
	}
#endif
	inline u32 bloom_n_blocks_for(u64 expected_candidates) {
		const u64 expected_unique = (expected_candidates + 1) / 2;
		u64 target_bytes = expected_unique * 16 / 8;

		if(target_bytes <  (16ull << 20)) {
			target_bytes = (16ull << 20);
		}

		if(target_bytes > (256ull << 20)) {
			target_bytes = (256ull << 20);
		}

		u64 target_blocks = target_bytes / (BLOOM_BLOCK_BITS / 8);
		u64 n = 1;

		while(n < target_blocks) {
			n <<= 1;
		}

		return (u32)n;
	}
} // namespace so

#endif // #ifndef BLOOM_CUH

