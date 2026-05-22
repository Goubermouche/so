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

#define KB(n) (((u64)(n)) << 10)
#define MB(n) (((u64)(n)) << 20)
#define GB(n) (((u64)(n)) << 30)
#define TB(n) (((u64)(n)) << 40)

#define Min(a, b) (((a) < (b)) ? (a) : (b))
#define Max(a, b) (((a) > (b)) ? (a) : (b))

using u8 = uint8_t;
using u16 = uint16_t;
using u32 = uint32_t;
using u64 = uint64_t;

using i8 = int8_t;
using i16 = int16_t;
using i32 = int32_t;
using i64 = int64_t;

using f32 = float;
using f64 = double;
using b32 = bool;
using c8 = char;

static inline f64 get_time_ms() {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (f64)ts.tv_sec * 1000.0 + (f64)ts.tv_nsec / 1000000.0;
}

#endif // #ifndef TYPE_H
