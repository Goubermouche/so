#ifndef DEVICE_H
#define DEVICE_H

#include <cuda_runtime.h>
#include "type.h"

namespace so {
	inline void check_cuda(cudaError_t err, const char* msg) {
		if(err != cudaSuccess) {
			print_err("error: [{}]: {}\n", msg, cudaGetErrorString(err));
			flush();
			exit(1);
		}
	}

	inline i32 device_init() {
		i32 dev = 0;

		if(cudaGetDevice(&dev) != cudaSuccess) {
			print_err("error: no device found\n");
			return 1;
		}

		cudaDeviceProp p;
		if(cudaGetDeviceProperties(&p, dev) != cudaSuccess) {
			print_err("error: cannot query device properties\n");
			return 2;
		}

		const f64 mem_bw_gbs  = ((f64)p.memoryBusWidth / 8.0) * ((f64)p.memoryClockRate * 1000.0) * 2.0 / 1e9;
		const i32 max_threads = p.multiProcessorCount * p.maxThreadsPerMultiProcessor;
		const i32 max_warps   = max_threads / 32;

		print("device: {} (sm_{}{})\n", p.name, p.major, p.minor);
		print("        threads: {}\n", max_threads);
		print("        warps: {}\n", max_warps);
		print("        dram: {} GB @ {} GB/s\n", std::ceil(p.totalGlobalMem / (1024.0 * 1024.0 * 1024.0)), (i32)mem_bw_gbs);
		print("        L2: {}\n", p.l2CacheSize / 1024);
		print("        shared memory per block: {} KB\n", (int)p.sharedMemPerBlock / 1024);
		print("        SM clock: {} MHz\n", p.clockRate / 1000);
		print("        mem clock: {} MHz\n", p.memoryClockRate / 1000.0);

		return 0;
	}
} // namespace so

#ifdef __CUDACC__
	#define SO_HD __host__ __device__ __forceinline__
	#define SO_D  __device__ __forceinline__
#else
	#define SO_HD inline
	#define SO_D  inline
#endif // #ifdef __CUDACC__

#endif // #define DEVICE_H

