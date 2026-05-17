#ifndef UTL_STR_H
#define UTL_STR_H

#include "util/arena.h"
#include "util/array.h"

struct string : slice<c8> {
	string() : slice<c8>() {};
	string(c8* ptr, u64 len) : slice<c8>(ptr, len) {}
	string(const c8* c) {
		const c8* p = c;
		while(*p) { ++p; }
		ptr = (c8*)c;
		size = (u64)(p - c);
	}

	static string format(arena& a, const c8* fmt, ...) {
		va_list ap;
		va_start(ap, fmt);
		va_list ap2;
		va_copy(ap2, ap);
		int n = vsnprintf(0, 0, fmt, ap);
		va_end(ap);
		ASSERT(n >= 0, "string::format: vsnprintf failed\n");
		c8* dst = a.push<c8>((u64)n + 1);
		vsnprintf((c8*)dst, (u64)n + 1, fmt, ap2);
		va_end(ap2);
		return string(dst, (u64)n);
	}

	void pad(arena& a, u8 pad_byte, u64 target_size) {
		if(target_size <= size) { return; }
		const u64 pad_len = target_size - size;
		c8* dst = a.push<c8>(target_size);
		memcpy(dst, ptr, size);
		memset(dst + size, pad_byte, pad_len);
		ptr = dst;
		size = target_size;
	}

	b32 operator==(const c8* cstr) const {
		for(u64 i = 0; i < size; ++i) {
			if(cstr[i] == '\0' || ptr[i] != cstr[i]) { return false; }
		}
		return cstr[size] == '\0';
	}
};

inline string str_list_flatten(arena& a, const array<string>& parts, string sep) {
	const u64 n = parts.size;
	if(n == 0) { return string(); }

	u64 total = 0;
	for(u64 i = 0; i < n; ++i) { total += parts[i].size; }
	if(sep.size > 0 && n > 1) { total += sep.size * (n - 1); }
	c8* dst = a.push<c8>(total);
	u64 off = 0;

	for(u64 i = 0; i < n; ++i) {
		const string& s = parts[i];
		if(s.size > 0) {
			memcpy(dst + off, s.ptr, s.size);
			off += s.size;
		}
		if(sep.size > 0 && i + 1 < n) {
			memcpy(dst + off, sep.ptr, sep.size);
			off += sep.size;
		}
	}
	return string(dst, total);
}

#endif // #ifnded UTL_STR_H