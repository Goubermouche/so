#ifndef TYPE_H
#define TYPE_H

#include <algorithm>
#include <array>
#include <cctype>
#include <chrono>
#include <climits>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <sstream>
#include <stdint.h>
#include <unordered_map>
#include <vector>

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

template <typename key, typename type> using map = std::unordered_map<key, type>;

inline str pad_to_length(const str& s, char pad, u64 target_len) {
	u64 pad_len = (target_len > s.size()) ? (target_len - s.size()) : 0;
	return s + str(pad_len, pad);
}

#endif // #ifndef TYPE_H
