#ifndef UTL_ARENA_H
#define UTL_ARENA_H

#include "util/type.h"

#define ArenaDefaultBlockSize KB(2)
#define ArenaeDefaultAlign 8

#define ArenaPush(a, T, count) ((T*)arena_push_aligned((a), sizeof(T) * (count), alignof(T)))

typedef struct ArenaBlock {
	ArenaBlock* next;
	U64 size; // total bytes in base
	U64 used; // bytes currently used
	U8 base[1];
} ArenaBlock;

typedef struct Arena {
	ArenaBlock* head;
	U64 block_size;
} Arena;

Arena* arena_make(U64 block_size);
void arena_free(Arena* a);

ArenaBlock* arena_make_block(U64 size);
void* arena_push_aligned(Arena* a, U64 size, U64 align);
void arena_push_data(Arena* a, const void* src, U64 size);

#endif // UTL_ARENA_H