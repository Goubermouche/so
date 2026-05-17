#include "device.h"

void check_cuda(cudaError_t err, const c8* msg) {
	if(err != cudaSuccess) {
		fprintf(stderr, "error: [%s]: %s\n", msg, cudaGetErrorString(err));
		fflush(stderr);
		exit(1);
	}
}

void dmalloc(void** ptr, u64 size) {
	check_cuda(cudaMalloc(ptr, size), "cudaMalloc");
}

void hmalloc(void** ptr, u64 size) {
	check_cuda(cudaMallocHost(ptr, size), "cudaMallocHost");
}

void htod_memcpy(void* dst, const void* src, u64 count) {
	check_cuda(cudaMemcpy(dst, src, count, cudaMemcpyHostToDevice),
						 "cudaMemcpyHostToDevice");
}

void dtoh_memcpy(void* dst, const void* src, u64 count) {
	check_cuda(cudaMemcpy(dst, src, count, cudaMemcpyDeviceToHost),
						 "cudaMemcpyDeviceToHost");
}

i32 device_init() {
	i32 dev = 0;

	if(cudaGetDevice(&dev) != cudaSuccess) {
		fprintf(stderr, "error: no device found\n");
		return 1;
	}

	cudaDeviceProp p;
	if(cudaGetDeviceProperties(&p, dev) != cudaSuccess) {
		fprintf(stderr, "error: cannot query device properties\n");
		return 2;
	}

	const f64 bus_width_bytes = (f64)p.memoryBusWidth / 8.0;
	const f64 mem_bw_gbs =
		bus_width_bytes * ((f64)p.memoryClockRate * 1000.0) * 2.0 / 1e9;
	const i32 max_threads = p.multiProcessorCount * p.maxThreadsPerMultiProcessor;
	const i32 max_warps = max_threads / 32;

	printf("device: %s (sm_%u%u)\n", p.name, p.major, p.minor);
	printf("  threads: %u\n", max_threads);
	printf("  warps: %u\n", max_warps);
	printf("  dram: %.0fGB @ %dGB/s\n", ceil((f64)p.totalGlobalMem / GB(1)),
				 (i32)mem_bw_gbs);
	printf("  L2: %zuKB\n", p.l2CacheSize / KB(1));
	printf("  shared memory per block: %zuKB\n", p.sharedMemPerBlock / KB(1));
	printf("  SM clock: %dMHz\n", p.clockRate / 1000);
	printf("  mem clock: %dMHz\n", p.memoryClockRate / 1000);

	return 0;
}