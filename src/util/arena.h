#ifndef UTL_ARENA_H
#define UTL_ARENA_H

#include "util/type.h"

#define ARENA_DEFAULT_BLOCK_SIZE MB(1)
#define ARENA_DEFAULT_ALIGN 8

typedef struct arena_block {
	struct arena_block* next;
	u64 size; // total bytes in base
	u64 used; // bytes currently used
	u8 base[1];
} arena_block;

typedef struct arena {
	arena_block* head;
	u64 block_size;
} arena;

arena arena_make(u64 block_size);
void arena_release(arena* a);

void* arena_push_aligned(arena* a, u64 size, u64 align);
void* arena_push(arena* a, u64 size);

arena_block* arena_block_make(u64 size);

#define push_array(a, T, n) ((T*)arena_push_aligned((a), sizeof(T) * (u64)(n), alignof(T)))
#define push_array_zero(a, T, n)                                                                   \
	((T*)memset(arena_push_aligned((a), sizeof(T) * (u64)(n), alignof(T)), 0, sizeof(T) * (u64)(n)))
#define push_struct(a, T) push_array((a), T, 1)
#define push_struct_zero(a, T) push_array_zero((a), T, 1)

#endif // #ifndef UTL_ARENA_H
