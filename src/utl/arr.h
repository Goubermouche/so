#ifndef UTL_arr_H
#define UTL_arr_H

#include "utl/arena.h"

// TODO: temp solution

#define ARR_DECL(T, NAME)                                                                          \
	typedef struct NAME {                                                                            \
		T* v;                                                                                          \
		u64 size;                                                                                      \
		u64 cap;                                                                                       \
		arena* a;                                                                                      \
	} NAME;                                                                                          \
                                                                                                   \
	static inline NAME NAME##_make(arena* a) {                                                       \
		NAME r;                                                                                        \
		r.v = 0;                                                                                       \
		r.size = 0;                                                                                    \
		r.cap = 0;                                                                                     \
		r.a = a;                                                                                       \
		return r;                                                                                      \
	}                                                                                                \
                                                                                                   \
	static inline void NAME##_reserve(NAME* arr, u64 want) {                                         \
		if(arr->cap >= want) return;                                                                   \
		u64 nc = arr->cap ? arr->cap : 16;                                                             \
		while(nc < want) nc = nc + (nc >> 1) + 1;                                                      \
		T* nv = push_array(arr->a, T, nc);                                                             \
		if(arr->size) memcpy(nv, arr->v, sizeof(T) * arr->size);                                       \
		arr->v = nv;                                                                                   \
		arr->cap = nc;                                                                                 \
	}                                                                                                \
                                                                                                   \
	static inline void NAME##_resize(NAME* arr, u64 n) {                                             \
		NAME##_reserve(arr, n);                                                                        \
		if(n > arr->size) { memset(arr->v + arr->size, 0, sizeof(T) * (n - arr->size)); }              \
		arr->size = n;                                                                                 \
	}                                                                                                \
                                                                                                   \
	static inline void NAME##_push(NAME* arr, T value) {                                             \
		if(arr->size + 1 > arr->cap) NAME##_reserve(arr, arr->size + 1);                               \
		arr->v[arr->size++] = value;                                                                   \
	}                                                                                                \
                                                                                                   \
	static inline void NAME##_assign(NAME* arr, const T* src, u64 n) {                               \
		NAME##_reserve(arr, n);                                                                        \
		if(n) memcpy(arr->v, src, sizeof(T) * n);                                                      \
		arr->size = n;                                                                                 \
	}                                                                                                \
                                                                                                   \
	static inline b32 NAME##_empty(const NAME* arr) { return arr->size == 0; }
#endif // #ifndef UTL_arr_H