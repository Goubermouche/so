#ifndef UTL_STR_H
#define UTL_STR_H

#include "util/arena.h"

#define S8(s) ((S8){(C8*)("" s), sizeof("" s) - 1})

typedef struct S8 {
	C8* ptr;
	U64 size;
} S8;

S8 str_make(C8* ptr, U64 size);
S8 str_make_from_cstr(const C8* c);
S8 str_make_format(Arena* a, const C8* fmt, ...);

S8 str_pad(Arena* a, S8 s, U8 pad_byte, U64 target_size);
B32 str_match_cstr(S8 s, const C8* cstr);
B32 str_match(S8 a, S8 b);

#endif // UTL_STR_H