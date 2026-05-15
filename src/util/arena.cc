#include "arena.h"

arena_block* arena_block_make(u64 size) {
	arena_block* b = (arena_block*)malloc(sizeof(arena_block) + size);
	ASSERT(b != 0, "arena: out of memory (block %zu bytes)\n", size);
	b->next = 0;
	b->size = size;
	b->used = 0;
	return b;
}

arena arena_make(u64 block_size) {
	arena a;
	a.block_size = block_size ? block_size : ARENA_DEFAULT_BLOCK_SIZE;
	a.head = arena_block_make(a.block_size);
	return a;
}

void arena_release(arena* a) {
	arena_block* b = a->head;
	while(b) {
		arena_block* next = b->next;
		free(b);
		b = next;
	}
	a->head = 0;
}

void* arena_push_aligned(arena* a, u64 size, u64 align) {
	arena_block* b = a->head;
	const u64 mask = align - 1;
	u64 pad = ((align - (b->used & mask)) & mask);

	if(b->used + pad + size > b->size) {
		const u64 want = size + (align - 1);
		const u64 bs = (want > a->block_size) ? want : a->block_size;
		arena_block* nb = arena_block_make(bs);
		nb->next = a->head;
		a->head = nb;
		b = nb;
		pad = ((align - ((u64)(uintptr_t)b->base & mask)) & mask);
	}

	u8* p = b->base + b->used + pad;
	b->used += pad + size;
	return p;
}

void* arena_push(arena* a, u64 size) { return arena_push_aligned(a, size, ARENA_DEFAULT_ALIGN); }
