#include "string.h"

S8 s8_make(C8* ptr, U64 size) {
	S8 r;
	r.ptr = ptr;
	r.size = size;
	return r;
}

S8 s8_make_fmt(Arena* a, const C8* fmt, ...) {
	va_list ap;
	va_start(ap, fmt);
	va_list ap2;
	va_copy(ap2, ap);
	int n = vsnprintf(0, 0, fmt, ap);
	va_end(ap);
	Assert(n >= 0, "s8_make_fmt: vsnprintf failed\n");
	C8* dst = ArenaPush(a, C8, (U64)n + 1);
	vsnprintf(dst, (U64)n + 1, fmt, ap2);
	va_end(ap2);
	S8 r;
	r.ptr = dst;
	r.size = (U64)n;
	return r;
}

B32 s8_equals_cstr(S8 s, const C8* cstr) {
	for(U64 i = 0; i < s.size; ++i) {
		if(cstr[i] == '\0' || s.ptr[i] != cstr[i]) { return false; }
	}
	return cstr[s.size] == '\0';
}

B32 s8_equals(S8 a, S8 b) {
	if(a.size != b.size) return false;
	if(a.size == 0) return true;
	return memcmp(a.ptr, b.ptr, a.size) == 0;
}