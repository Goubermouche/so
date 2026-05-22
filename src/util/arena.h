#ifndef UTL_ARENA_H
#define UTL_ARENA_H
#include "util/type.h"

#define ArenaDefaultBlockSize KB(2)
#define ArenaeDefaultAlign 8

#define ArenaPush(a, T, count) ((T*)arena_push_aligned((a), sizeof(T) * (count), alignof(T)))

typedef struct ArenaBlock ArenaBlock;
struct ArenaBlock {
	ArenaBlock* next;
	U64 size; // total bytes in base
	U64 used; // bytes currently used
	U8 base[1];
};

typedef struct Arena Arena;
struct Arena {
	ArenaBlock* head;
	U64 block_size;
};

Arena* arena_make(U64 block_size);
void arena_free(Arena* a);

ArenaBlock* arena_make_block(U64 size);
void* arena_push_aligned(Arena* a, U64 size, U64 align);

#endif // UTL_ARENA_H