#ifndef DEVICE_H
#define DEVICE_H
#include "type.h"
#include <cuda_runtime.h>

#ifdef __CUDACC__
#define HostDevice __host__ __device__ __forceinline__
#define Device __device__ __forceinline__
#else
#define HostDevice inline
#define Device inline
#endif // #ifdef __CUDACC__

void dmalloc(void** ptr, U64 size);
void hmalloc(void** ptr, U64 size);
void htod_memcpy(void* dst, const void* src, U64 count);
void dtoh_memcpy(void* dst, const void* src, U64 count);
void check_cuda(cudaError_t err, const C8* msg);
I32 device_init();

#define DeviceExclusiveSumScanBlock 256
#define DeviceExclusiveSumScanTile DeviceExclusiveSumScanBlock

void device_exclusive_sum(void* d_tmp, U64* tmp_bytes, U32* d_in, U64* d_out, I32 n);

#endif // #define DEVICE_H