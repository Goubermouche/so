#ifndef UTL_STR_H
#define UTL_STR_H

#include "util/arena.h"
#include "util/array.h"

struct string : slice<C8> {
	string() : slice<C8>() {};
	string(C8* ptr, U64 len) : slice<C8>(ptr, len) {}
	string(const C8* c) {
		const C8* p = c;
		while(*p) { ++p; }
		ptr = (C8*)c;
		size = (U64)(p - c);
	}

	static string format(arena& a, const C8* fmt, ...) {
		va_list ap;
		va_start(ap, fmt);
		va_list ap2;
		va_copy(ap2, ap);
		int n = vsnprintf(0, 0, fmt, ap);
		va_end(ap);
		Assert(n >= 0, "string::format: vsnprintf failed\n");
		C8* dst = a.push<C8>((U64)n + 1);
		vsnprintf((C8*)dst, (U64)n + 1, fmt, ap2);
		va_end(ap2);
		return string(dst, (U64)n);
	}

	void pad(arena& a, U8 pad_byte, U64 target_size) {
		if(target_size <= size) { return; }
		const U64 pad_len = target_size - size;
		C8* dst = a.push<C8>(target_size);
		memcpy(dst, ptr, size);
		memset(dst + size, pad_byte, pad_len);
		ptr = dst;
		size = target_size;
	}

	B32 operator==(const C8* cstr) const {
		for(U64 i = 0; i < size; ++i) {
			if(cstr[i] == '\0' || ptr[i] != cstr[i]) { return false; }
		}
		return cstr[size] == '\0';
	}
};

inline string str_list_flatten(arena& a, const array<string>& parts, string sep) {
	const U64 n = parts.size;
	if(n == 0) { return string(); }

	U64 total = 0;
	for(U64 i = 0; i < n; ++i) { total += parts[i].size; }
	if(sep.size > 0 && n > 1) { total += sep.size * (n - 1); }
	C8* dst = a.push<C8>(total);
	U64 off = 0;

	for(U64 i = 0; i < n; ++i) {
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