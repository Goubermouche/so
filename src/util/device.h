#ifndef DEVICE_H
#define DEVICE_H

#include "type.h"
#include <cuda_runtime.h>

#ifdef __CUDACC__
#define SO_HD __host__ __device__ __forceinline__
#define SO_D __device__ __forceinline__
#else
#define SO_HD inline
#define SO_D inline
#endif // #ifdef __CUDACC__

void dmalloc(void** ptr, u64 size);
void hmalloc(void** ptr, u64 size);
void htod_memcpy(void* dst, const void* src, u64 count);
void dtoh_memcpy(void* dst, const void* src, u64 count);

void check_cuda(cudaError_t err, const char* msg);

i32 device_init();

#endif // #define DEVICE_H
