#include "string.h"

Str str_make(C8* ptr, U64 size) {
	Str r;
	r.ptr = ptr;
	r.size = size;
	return r;
}

Str str_make_from_cstr(const C8* c) {
	const C8* p = c;
	while(*p) { ++p; }
	Str r;
	r.ptr = (C8*)c;
	r.size = (U64)(p - c);
	return r;
}

Str str_make_format(Arena* a, const C8* fmt, ...) {
	va_list ap;
	va_start(ap, fmt);
	va_list ap2;
	va_copy(ap2, ap);
	int n = vsnprintf(0, 0, fmt, ap);
	va_end(ap);
	Assert(n >= 0, "str_make_format: vsnprintf failed\n");
	C8* dst = ArenaPush(a, C8, (U64)n + 1);
	vsnprintf(dst, (U64)n + 1, fmt, ap2);
	va_end(ap2);
	Str r;
	r.ptr = dst;
	r.size = (U64)n;
	return r;
}

Str str_pad(Arena* a, Str s, U8 pad_byte, U64 target_size) {
	if(target_size <= s.size) { return s; }
	U64 pad_len = target_size - s.size;
	C8* dst =  ArenaPush(a, C8, target_size);
	memcpy(dst, s.ptr, s.size);
	memset(dst + s.size, pad_byte, pad_len);
	Str r;
	r.ptr = dst;
	r.size = target_size;
	return r;
}

B32 str_match_cstr(Str s, const C8* cstr) {
	for(U64 i = 0; i < s.size; ++i) {
		if(cstr[i] == '\0' || s.ptr[i] != cstr[i]) { return 0; }
	}
	return cstr[s.size] == '\0';
}

Str str_list_flatten(Arena* a, const array<Str>& parts, Str sep) {
	U64 n = parts.size;
	if(n == 0) {
		Str r = {0};
		return r;
	}

	U64 total = 0;
	for(U64 i = 0; i < n; ++i) { total += parts[i].size; }
	if(sep.size > 0 && n > 1) { total += sep.size * (n - 1); }

	C8* dst = ArenaPush(a, C8, total);
	U64 off = 0;
	for(U64 i = 0; i < n; ++i) {
		Str s = parts[i];
		if(s.size > 0) {
			memcpy(dst + off, s.ptr, s.size);
			off += s.size;
		}
		if(sep.size > 0 && i + 1 < n) {
			memcpy(dst + off, sep.ptr, sep.size);
			off += sep.size;
		}
	}

	Str r;
	r.ptr = dst;
	r.size = total;
	return r;
}