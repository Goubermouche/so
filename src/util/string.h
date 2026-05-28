#ifndef UTL_STR_H
#define UTL_STR_H

#include "util/arena.h"

#define S8(s) ((S8){(C8*)("" s), sizeof("" s) - 1})

typedef struct S8 {
	C8* ptr;
	U64 size;
} S8;

S8 s8_make(C8* ptr, U64 size);
S8 s8_make_fmt(Arena* a, const C8* fmt, ...);

B32 s8_equals_cstr(S8 s, const C8* cstr);
B32 s8_equals(S8 a, S8 b);

#endif // UTL_STR_H