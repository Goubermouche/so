#ifndef TYPE_H
#define TYPE_H

#include <stdint.h>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <cmath>
#include <algorithm>
#include <vector>
#include <unordered_map>
#include <sstream>
#include <chrono>
#include <climits>
#include <array>

namespace sup {
	namespace type {
		using u8  = uint8_t;
		using u16 = uint16_t;
		using u32 = uint32_t;
		using u64 = uint64_t;

		using i8  = int8_t;
		using i16 = int16_t;
		using i32 = int32_t;
		using i64 = int64_t;

		using f32 = float;
		using f64 = double;

		using b32 = bool;

		using str = std::string;

		template<typename type>
		using arr = std::vector<type>;

		template<typename key, typename type>
		using map = std::unordered_map<key, type>;
	} // namespace type

	using namespace type;

	template<typename T>
	void format_arg(std::ostringstream& os, const char*& fmt, const T& arg) {
		while(*fmt) {
			if(*fmt == '{' && *(fmt + 1) == '}') {
				os << arg;
				fmt += 2;
				return;
			}

			os << *fmt++;
		}
	}

	template<typename... Args>
	void print(const char* fmt, const Args&... args) {
		std::ostringstream os;
		(format_arg(os, fmt, args), ...);
		while (*fmt) os << *fmt++;
		std::fputs(os.str().c_str(), stdout);
	}

	template<typename... Args>
	void print_err(const char* fmt, const Args&... args) {
		std::ostringstream os;
		(format_arg(os, fmt, args), ...);
		while (*fmt) os << *fmt++;
		std::fputs(os.str().c_str(), stderr);
	}

	inline void flush() {
		std::fflush(stdout);
	}

	inline str pad_to_length(const str& s, char pad, u64 target_len) {
		u64 pad_len = (target_len > s.size()) ? (target_len - s.size()) : 0;
		return s + str(pad_len, pad);
	}
} // namespace sup

#define HD __host__ __device__

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
#error "Unsupported platform!"
#endif

// #ifdef DEBUG_MODE
#define ASSERT(__condition, __message, ...)    \
  do {                                         \
    if(!(__condition)) {                       \
      sup::print_err(__message,## __VA_ARGS__); \
      sup::flush();                             \
      DEBUG_BREAK();                           \
    }                                          \
  } while(false)
// #else
// #define ASSERT(__condition, __message, ...)
// #endif

using namespace sup;

#endif // #ifndef TYPE_H

