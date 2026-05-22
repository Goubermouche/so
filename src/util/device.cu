#include "device.cuh"

void check_cuda(cudaError_t err, const c8* msg) {
	if(err != cudaSuccess) {
		fprintf(stderr, "error: [%s]: %s\n", msg, cudaGetErrorString(err));
		fflush(stderr);
		exit(1);
	}
}

void dmalloc(void** ptr, u64 size) { check_cuda(cudaMalloc(ptr, size), "cudaMalloc"); }
void hmalloc(void** ptr, u64 size) { check_cuda(cudaMallocHost(ptr, size), "cudaMallocHost"); }

void htod_memcpy(void* dst, const void* src, u64 count) {
	check_cuda(cudaMemcpy(dst, src, count, cudaMemcpyHostToDevice), "cudaMemcpyHostToDevice");
}

void dtoh_memcpy(void* dst, const void* src, u64 count) {
	check_cuda(cudaMemcpy(dst, src, count, cudaMemcpyDeviceToHost), "cudaMemcpyDeviceToHost");
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
	const f64 mem_bw_gbs = bus_width_bytes * ((f64)p.memoryClockRate * 1000.0) * 2.0 / 1e9;
	const i32 max_threads = p.multiProcessorCount * p.maxThreadsPerMultiProcessor;
	const i32 max_warps = max_threads / 32;
	printf("device: %s (sm_%u%u)\n", p.name, p.major, p.minor);
	printf("  threads: %u\n", max_threads);
	printf("  warps: %u\n", max_warps);
	printf("  dram: %.0fGB @ %dGB/s\n", ceil((f64)p.totalGlobalMem / GB(1)), (i32)mem_bw_gbs);
	printf("  L2: %zuKB\n", p.l2CacheSize / KB(1));
	printf("  shared memory per block: %zuKB\n", p.sharedMemPerBlock / KB(1));
	printf("  SM clock: %dMHz\n", p.clockRate / 1000);
	printf("  mem clock: %dMHz\n", p.memoryClockRate / 1000);
	return 0;
}

__global__ void scan_block_kernel(
	const u32* __restrict__ d_in,
	u64* __restrict__ d_out,
	u64* __restrict__ d_block_sums,
	i32 n
) {
	__shared__ u64 smem[DeviceExclusiveSumScanBlock];

	const i32 tid = (i32)threadIdx.x;
	const i32 idx = (i32)blockIdx.x * DeviceExclusiveSumScanTile + tid;
	const u64 val = (idx < n) ? (u64)d_in[idx] : 0ull;

	// convert to exclusive by shifting
	smem[tid] = (tid == 0) ? 0ull : val;
	smem[tid] = val;
	__syncthreads();

	// scan
	for(i32 offset = 1; offset < DeviceExclusiveSumScanBlock; offset <<= 1) {
		u64 add = (tid >= offset) ? smem[tid - offset] : 0ull;
		__syncthreads();
		smem[tid] += add;
		__syncthreads();
	}

	const u64 inclusive = smem[tid];
	const u64 exclusive = inclusive - val;

	if(idx < n) d_out[idx] = exclusive;

	if(tid == DeviceExclusiveSumScanBlock - 1 && d_block_sums) {
		d_block_sums[blockIdx.x] = inclusive; 
	}
}

__global__ void scan_block_sums_serial(
	const u64* __restrict__ d_block_sums,
	u64* __restrict__ d_block_offsets,
	i32 n_blocks
) {
	if(threadIdx.x != 0 || blockIdx.x != 0) return;
	u64 acc = 0;
	for(i32 i = 0; i < n_blocks; ++i) {
		d_block_offsets[i] = acc;
		acc += d_block_sums[i];
	}
}

__global__ void scan_add_offsets_kernel(
	u64* __restrict__ d_out,
	const u64* __restrict__ d_block_offsets,
	i32 n
) {
	const i32 idx = (i32)blockIdx.x * DeviceExclusiveSumScanTile + (i32)threadIdx.x;
	if(idx >= n) return;
	if(blockIdx.x == 0) return; // offset is 0
	d_out[idx] += d_block_offsets[blockIdx.x];
}

void device_exclusive_sum(void* d_tmp, u64* tmp_bytes, const u32* d_in, u64* d_out, i32 n) {
	if(n <= 0) {
		if(d_tmp == 0) *tmp_bytes = 1;
		return;
	}

	const i32 n_blocks = (n + DeviceExclusiveSumScanTile - 1) / DeviceExclusiveSumScanTile;
	const u64 needed = (u64)n_blocks * sizeof(u64) * 2;

	if(d_tmp == 0) {
		*tmp_bytes = Max(needed, 1);
		return;
	}

	u64* d_block_sums = (u64*)d_tmp;
	u64* d_block_offsets = d_block_sums + n_blocks;

	scan_block_kernel<<<n_blocks, DeviceExclusiveSumScanBlock>>>(d_in, d_out, d_block_sums, n);
	check_cuda(cudaGetLastError(), "scan_block_kernel");

	scan_block_sums_serial<<<1, 1>>>(d_block_sums, d_block_offsets, n_blocks);
	check_cuda(cudaGetLastError(), "scan_block_sums_serial");

	if(n_blocks > 1) {
		scan_add_offsets_kernel<<<n_blocks, DeviceExclusiveSumScanBlock>>>(d_out, d_block_offsets, n);
		check_cuda(cudaGetLastError(), "scan_add_offsets_kernel");
	}
}