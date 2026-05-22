#include "arena.h"

Arena* arena_make(U64 block_size) {
	if(block_size == 0) { block_size = ArenaDefaultBlockSize; }
	Arena* a = (Arena*)malloc(sizeof(Arena));
	Assert(a != 0, "arena_make: malloc failed\n");
	a->block_size = block_size;
	a->head = arena_make_block(block_size);
	return a;
}

void arena_free(Arena* a) {
	if(a == 0) { return; }
	ArenaBlock* b = a->head;
	while(b) {
		ArenaBlock* next = b->next;
		free(b);
		b = next;
	}
	a->head = 0;
	free(a);
}

ArenaBlock* arena_make_block(U64 size) {
	ArenaBlock* b = (ArenaBlock*)malloc(sizeof(ArenaBlock) + size);
	Assert(b != 0, "arena_make_block: malloc failed with size = %llu\n", (unsigned long long)size);
	b->next = 0;
	b->size = size;
	b->used = 0;
	return b;
}

void* arena_push_aligned(Arena* a, U64 size, U64 align) {
	ArenaBlock* b = a->head;
	U64 mask = align - 1;
	U64 pad = (align - (b->used & mask)) & mask;

	if(b->used + pad + size > b->size) {
		U64 want = size + (align - 1);
		U64 bs = (want > a->block_size) ? want : a->block_size;
		ArenaBlock* nb = arena_make_block(bs);
		nb->next = a->head;
		a->head = nb;
		b = nb;
		pad = (align - ((U64)(uintptr_t)b->base & mask)) & mask;
	}

	U8* p = b->base + b->used + pad;
	b->used += pad + size;
	return p;
}