#ifndef UTL_STR_H
#define UTL_STR_H

#include "util/arena.h"

typedef struct str {
	u8* str;
	u64 size;
} str;

// string list
typedef struct str_node {
	struct str_node* next;
	str s;
} str_node;

typedef struct str_list {
	str_node* first;
	str_node* last;
	u64 node_count;
	u64 total_size;
} str_list;

#define STR_LIT(s) str_make((u8*)("" s ""), sizeof(s) - 1)

str str_make(u8* p, u64 n);
str str_cstring(const char* c);
b32 str_eq(str a, str b);
b32 str_eq_cstr(str a, const char* c);
str str_copy(arena* a, str s);
str str_push_fmt(arena* a, const char* fmt, ...);
str str_pad_to_len(arena* a, str s, u8 pad, u64 target_len);

// string list
void str_list_push(arena* a, str_list* list, str s);
void str_list_push_fmt(arena* a, str_list* list, const char* fmt, ...);
str str_list_flatten(arena* a, str_list* list, str sep);

#endif // #ifnded UTL_STR_H