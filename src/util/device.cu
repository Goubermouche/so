#include "device.cuh"

void check_cuda(cudaError_t err, const C8* msg) {
	if(err != cudaSuccess) {
		fprintf(stderr, "error: [%s]: %s\n", msg, cudaGetErrorString(err));
		fflush(stderr);
		exit(1);
	}
}

void dmalloc(void** ptr, U64 size) { check_cuda(cudaMalloc(ptr, size), "cudaMalloc"); }
void hmalloc(void** ptr, U64 size) { check_cuda(cudaMallocHost(ptr, size), "cudaMallocHost"); }

void htod_memcpy(void* dst, const void* src, U64 count) {
	check_cuda(cudaMemcpy(dst, src, count, cudaMemcpyHostToDevice), "cudaMemcpyHostToDevice");
}

void dtoh_memcpy(void* dst, const void* src, U64 count) {
	check_cuda(cudaMemcpy(dst, src, count, cudaMemcpyDeviceToHost), "cudaMemcpyDeviceToHost");
}

I32 device_init() {
	I32 dev = 0;
	if(cudaGetDevice(&dev) != cudaSuccess) {
		fprintf(stderr, "error: no device found\n");
		return 1;
	}
	cudaDeviceProp p;
	if(cudaGetDeviceProperties(&p, dev) != cudaSuccess) {
		fprintf(stderr, "error: cannot query device properties\n");
		return 2;
	}
	F64 bus_width_bytes = (F64)p.memoryBusWidth / 8.0;
	F64 mem_bw_gbs = bus_width_bytes * ((F64)p.memoryClockRate * 1000.0) * 2.0 / 1e9;
	I32 max_threads = p.multiProcessorCount * p.maxThreadsPerMultiProcessor;
	I32 max_warps = max_threads / 32;
	printf("device: %s (sm_%u%u)\n", p.name, p.major, p.minor);
	printf("  threads: %u\n", max_threads);
	printf("  warps: %u\n", max_warps);
	printf("  dram: %.0fGB @ %dGB/s\n", ceil((F64)p.totalGlobalMem / GB(1)), (I32)mem_bw_gbs);
	printf("  L2: %zuKB\n", p.l2CacheSize / KB(1));
	printf("  shared memory per block: %zuKB\n", p.sharedMemPerBlock / KB(1));
	printf("  SM clock: %dMHz\n", p.clockRate / 1000);
	printf("  mem clock: %dMHz\n", p.memoryClockRate / 1000);
	return 0;
}

__global__ void scan_block_kernel(
	U32* __restrict__ d_in,
	U64* __restrict__ d_out,
	U64* __restrict__ d_block_sums,
	I32 n
) {
	__shared__ U64 smem[DeviceExclusiveSumScanBlock];

	I32 tid = (I32)threadIdx.x;
	I32 idx = (I32)blockIdx.x * DeviceExclusiveSumScanTile + tid;
	U64 val = (idx < n) ? (U64)d_in[idx] : 0ull;

	// convert to exclusive by shifting
	smem[tid] = (tid == 0) ? 0ull : val;
	smem[tid] = val;
	__syncthreads();

	// scan
	for(I32 offset = 1; offset < DeviceExclusiveSumScanBlock; offset <<= 1) {
		U64 add = (tid >= offset) ? smem[tid - offset] : 0ull;
		__syncthreads();
		smem[tid] += add;
		__syncthreads();
	}

	U64 inclusive = smem[tid];
	U64 exclusive = inclusive - val;

	if(idx < n) d_out[idx] = exclusive;

	if(tid == DeviceExclusiveSumScanBlock - 1 && d_block_sums) {
		d_block_sums[blockIdx.x] = inclusive; 
	}
}

__global__ void scan_block_sums_serial(
	U64* __restrict__ d_block_sums,
	U64* __restrict__ d_block_offsets,
	I32 n_blocks
) {
	if(threadIdx.x != 0 || blockIdx.x != 0) return;
	U64 acc = 0;
	for(I32 i = 0; i < n_blocks; ++i) {
		d_block_offsets[i] = acc;
		acc += d_block_sums[i];
	}
}

__global__ void scan_add_offsets_kernel(
	U64* __restrict__ d_out,
	U64* __restrict__ d_block_offsets,
	I32 n
) {
	I32 idx = (I32)blockIdx.x * DeviceExclusiveSumScanTile + (I32)threadIdx.x;
	if(idx >= n) return;
	if(blockIdx.x == 0) return; // offset is 0
	d_out[idx] += d_block_offsets[blockIdx.x];
}

void device_exclusive_sum(void* d_tmp, U64* tmp_bytes, U32* d_in, U64* d_out, I32 n) {
	if(n <= 0) {
		if(d_tmp == 0) *tmp_bytes = 1;
		return;
	}

	I32 n_blocks = (n + DeviceExclusiveSumScanTile - 1) / DeviceExclusiveSumScanTile;
	U64 needed = (U64)n_blocks * sizeof(U64) * 2;

	if(d_tmp == 0) {
		*tmp_bytes = Max(needed, 1);
		return;
	}

	U64* d_block_sums = (U64*)d_tmp;
	U64* d_block_offsets = d_block_sums + n_blocks;

	scan_block_kernel<<<n_blocks, DeviceExclusiveSumScanBlock>>>(d_in, d_out, d_block_sums, n);
	check_cuda(cudaGetLastError(), "scan_block_kernel");

	scan_block_sums_serial<<<1, 1>>>(d_block_sums, d_block_offsets, n_blocks);
	check_cuda(cudaGetLastError(), "scan_block_sums_serial");

	if(n_blocks > 1) {
		scan_add_offsets_kernel<<<n_blocks, DeviceExclusiveSumScanBlock>>>(d_out, d_block_offsets, n);
		check_cuda(cudaGetLastError(), "scan_add_offsets_kernel");
	}
}