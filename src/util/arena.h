#ifndef UTL_ARENA_H
#define UTL_ARENA_H

#include "util/type.h"

struct arena {
	static constexpr u64 DEFAULT_BLOCK_SIZE = KB(2);
	static constexpr u64 DEFAULT_ALIGN = 8;

	struct block {
		block* next;
		u64 size; // total bytes in base
		u64 used; // bytes currently used
		u8 base[1];
	};

	arena(u64 block_size = DEFAULT_BLOCK_SIZE) : block_size(block_size) {
		head = make_block(block_size);
	}

	~arena() {
		block* b = head;
		while(b) {
			block* next = b->next;
			free(b);
			b = next;
		}
		head = 0;
	}

	void* push(u64 size, u64 align = DEFAULT_ALIGN) {
		block* b = head;
		const u64 mask = align - 1;
		u64 pad = ((align - (b->used & mask)) & mask);

		if(b->used + pad + size > b->size) {
			const u64 want = size + (align - 1);
			const u64 bs = (want > block_size) ? want : block_size;
			block* nb = make_block(bs);
			nb->next = head;
			head = nb;
			b = nb;
			pad = ((align - ((u64)(uintptr_t)b->base & mask)) & mask);
		}

		u8* p = b->base + b->used + pad;
		b->used += pad + size;
		return p;
	}

	template<typename T> T* push(u64 count) {
		return (T*)push(sizeof(T) * count, alignof(T));
	}

	block* make_block(u64 size) {
		block* b = (block*)malloc(sizeof(block) + size);
		Assert(b != 0, "arena::make_block: malloc failed with size = %zu\n", size);
		b->next = 0;
		b->size = size;
		b->used = 0;
		return b;
	}

	block* head;
	u64 block_size;
};

#endif // #ifndef UTL_ARENA_H
