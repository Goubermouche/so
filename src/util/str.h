#ifndef UTL_STR_H
#define UTL_STR_H

#include "util/arena.h"
#include "util/arr.h"

struct str : slice<char> {
	str() : slice<char>() {};
	str(char* ptr, u64 len) : slice<char>(ptr, len) {}
	str(const char* c) {
		const char* p = c;
		while(*p) { ++p; }
		ptr = (char*)c;
		size = (u64)(p - c);
	}

	static str format(arena& a, const char* fmt, ...) {
		va_list ap;
		va_start(ap, fmt);
		va_list ap2;
		va_copy(ap2, ap);
		int n = vsnprintf(0, 0, fmt, ap);
		va_end(ap);
		ASSERT(n >= 0, "str::format: vsnprintf failed\n");
		char* dst = PUSH_ARRAY(&a, char, (u64)n + 1);
		vsnprintf((char*)dst, (u64)n + 1, fmt, ap2);
		va_end(ap2);
		return str(dst, (u64)n);
	}

	void pad(arena& a, u8 pad_byte, u64 target_size) {
		if(target_size <= size) { return; }
		const u64 pad_len = target_size - size;
		char* dst = PUSH_ARRAY(&a, char, target_size);
		memcpy(dst, ptr, size);
		memset(dst + size, pad_byte, pad_len);
		ptr = dst;
		size = target_size;
	}

	b32 operator==(const char* cstr) const {
		for(u64 i = 0; i < size; ++i) {
			if(cstr[i] == '\0' || ptr[i] != cstr[i]) { return false; }
		}
		return cstr[size] == '\0';
	}
};

inline str str_list_flatten(arena* a, const array<str>& parts, str sep) {
	const u64 n = parts.size();
	if(n == 0) { return str(); }

	u64 total = 0;
	for(u64 i = 0; i < n; ++i) { total += parts[i].size; }
	if(sep.size > 0 && n > 1) { total += sep.size * (n - 1); }
	char* dst = PUSH_ARRAY(a, char, total);
	u64 off = 0;

	for(u64 i = 0; i < n; ++i) {
		const str& s = parts[i];
		if(s.size > 0) {
			memcpy(dst + off, s.ptr, s.size);
			off += s.size;
		}
		if(sep.size > 0 && i + 1 < n) {
			memcpy(dst + off, sep.ptr, sep.size);
			off += sep.size;
		}
	}
	return str(dst, total);
}

#endif // #ifnded UTL_STR_H