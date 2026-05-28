#ifndef TYPE_H
#define TYPE_H

#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifdef Debug
#define DebugMode
#else
#define ReleaseMode
#endif // #ifdef Debug

#ifdef _WIN32
// windows
#include <intrin.h>

#define DebugBreak() __debugbreak()
#define SystemWindows
#elif __linux__
// linux
#include <signal.h>

#define DebugBreak() raise(SIGTRAP)
#define SystemLinux
#else
// unknown system
#error "error: unsupported platform!"
#endif // #ifdef _WIN32

// #ifdef DebugMode
#define Assert(__condition, __message, ...)                                                        \
	do {                                                                                             \
		if(!(__condition)) {                                                                           \
			fprintf(stderr, __message, ##__VA_ARGS__);                                                   \
			fflush(stderr);                                                                              \
			DebugBreak();                                                                                \
		}                                                                                              \
	} while(false)
// #else
// #define Assert(__condition, __message, ...)
// #endif // #ifdef DebugMode

#define KB(n) (((U64)(n)) << 10)
#define MB(n) (((U64)(n)) << 20)
#define GB(n) (((U64)(n)) << 30)
#define TB(n) (((U64)(n)) << 40)

#define Min(a, b) (((a) < (b)) ? (a) : (b))
#define Max(a, b) (((a) > (b)) ? (a) : (b))

typedef uint8_t U8;
typedef uint16_t U16;
typedef uint32_t U32;
typedef uint64_t U64;

typedef int8_t I8;
typedef int16_t I16;
typedef int32_t I32;
typedef int64_t I64;

typedef float F32;
typedef double F64;
typedef bool B32;
typedef char C8;

static inline F64 get_time_ms() {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (F64)ts.tv_sec * 1000.0 + (F64)ts.tv_nsec / 1000000.0;
}

#endif // #ifndef TYPE_H
