#ifndef TYPE_H
#define TYPE_H

#include<stdint.h>
#include<cctype>
#include<cstdio>
#include<string>
#include<vector>
#include<unordered_map>
#include<sstream>

namespace so {
	namespace type {
		using u8  = uint8_t;
		using u16 = uint16_t;
		using u32 = uint32_t;
		using u64 = uint64_t;

		using i8  = int8_t;
		using i16 = int16_t;
		using i32 = int32_t;
		using i64 = int64_t;

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
} // namespace so

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
      so::print_err(__message,## __VA_ARGS__); \
      so::flush();                             \
      DEBUG_BREAK();                           \
    }                                          \
  } while(false)
// #else
// #define ASSERT(__condition, __message, ...)
// #endif

#endif // #ifndef TYPE_H

