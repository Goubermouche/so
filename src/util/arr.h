#ifndef UTL_arr_H
#define UTL_arr_H

#include "util/arena.h"
#include <vector> // TODO

template<typename T> struct slice {
	slice() : ptr(0), size(0) {}
	slice(T* ptr, u64 len) : ptr(ptr), size(len) {}

	b32 operator==(const slice<T>& other) const {
		if(other.size != size) { return false; }
		return memcmp(other.ptr, ptr, size * sizeof(T)) == 0;
	}

	T& operator[](u64 i) { return ptr[i]; }
	const T& operator[](u64 i) const { return ptr[i]; }

	T* ptr;
	u64 size;
};

// TODO:
template<typename T> using array = std::vector<T>;

#endif // #ifndef UTL_arr_H