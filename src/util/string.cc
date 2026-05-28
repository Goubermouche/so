#include "string.h"

S8 str_make(C8* ptr, U64 size) {
	S8 r;
	r.ptr = ptr;
	r.size = size;
	return r;
}

S8 str_make_from_cstr(const C8* c) {
	const C8* p = c;
	while(*p) { ++p; }
	S8 r;
	r.ptr = (C8*)c;
	r.size = (U64)(p - c);
	return r;
}

S8 str_make_format(Arena* a, const C8* fmt, ...) {
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
	S8 r;
	r.ptr = dst;
	r.size = (U64)n;
	return r;
}

S8 str_pad(Arena* a, S8 s, U8 pad_byte, U64 target_size) {
	if(target_size <= s.size) { return s; }
	U64 pad_len = target_size - s.size;
	C8* dst = ArenaPush(a, C8, target_size);
	memcpy(dst, s.ptr, s.size);
	memset(dst + s.size, pad_byte, pad_len);
	S8 r;
	r.ptr = dst;
	r.size = target_size;
	return r;
}

B32 str_match_cstr(S8 s, const C8* cstr) {
	for(U64 i = 0; i < s.size; ++i) {
		if(cstr[i] == '\0' || s.ptr[i] != cstr[i]) { return false; }
	}
	return cstr[s.size] == '\0';
}

B32 str_match(S8 a, S8 b) {
	if(a.size != b.size) return false;
	if(a.size == 0) return true;
	return memcmp(a.ptr, b.ptr, a.size) == 0;
}