#ifndef UTL_STR_H
#define UTL_STR_H

#include "util/arena.h"

#define StrLit(s) ((Str){(C8*)("" s), sizeof("" s) - 1})

typedef struct Str {
	C8* ptr;
	U64 size;
} Str;

Str str_make(C8* ptr, U64 size);
Str str_make_from_cstr(const C8* c);
Str str_make_format(Arena* a, const C8* fmt, ...);

Str str_pad(Arena* a, Str s, U8 pad_byte, U64 target_size);
B32 str_match_cstr(Str s, const C8* cstr);
B32 str_match(Str a, Str b);

#endif // UTL_STR_H