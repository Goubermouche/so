#ifndef TYPE_H
#define TYPE_H

#include <sstream>
#include <vector>

#include <math.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>

#ifdef DEBUG
#define DEBUG_MODE
#else
#define RELEASE_MODE
#endif

#ifdef _WIN32
// windows
#include <intrin.h>

#define DEBUG_BREAK() __debugbreak()
#define SYSTEM_WINDOWS
#elif __linux__
// linux
#include <signal.h>

#define DEBUG_BREAK() raise(SIGTRAP)
#define SYSTEM_LINUX
#else
// unknown system
#error "unsupported platform!"
#endif

// #ifdef DEBUG_MODE
#define ASSERT(__condition, __message, ...)                                                        \
	do {                                                                                             \
		if(!(__condition)) {                                                                           \
			fprintf(stderr, __message, ##__VA_ARGS__);                                                   \
			fflush(stderr);                                                                              \
			DEBUG_BREAK();                                                                               \
		}                                                                                              \
	} while(false)
// #else
// #define ASSERT(__condition, __message, ...)
// #endif

#define KB(n) (((u64)(n)) << 10)
#define MB(n) (((u64)(n)) << 20)
#define GB(n) (((u64)(n)) << 30)
#define TB(n) (((u64)(n)) << 40)

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;

typedef int8_t i8;
typedef int16_t i16;
typedef int32_t i32;
typedef int64_t i64;

typedef float f32;
typedef double f64;
typedef bool b32;

using str = std::string;

template <typename type> using arr = std::vector<type>;

inline str pad_to_length(const str& s, char pad, u64 target_len) {
	u64 pad_len = (target_len > s.size()) ? (target_len - s.size()) : 0;
	return s + str(pad_len, pad);
}

static inline f64 get_time_ms(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (f64)ts.tv_sec * 1000.0 + (f64)ts.tv_nsec / 1000000.0;
}

#endif // #ifndef TYPE_H
