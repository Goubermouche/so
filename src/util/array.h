#ifndef UTL_arr_H
#define UTL_arr_H

#include "util/type.h"

template<typename T> struct slice {
	slice() : ptr(0), size(0) {}
	slice(T* ptr, U64 len) : ptr(ptr), size(len) {}

	B32 operator==(const slice<T>& other) const {
		if(other.size != size) { return false; }
		return memcmp(other.ptr, ptr, size * sizeof(T)) == 0;
	}

	T& operator[](U64 i) { return ptr[i]; }
	const T& operator[](U64 i) const { return ptr[i]; }

	T* ptr;
	U64 size;
};

template<typename T> struct array {
	array() : ptr(0), size(0), cap(0) {}
	array(U64 n) : ptr(0), size(0), cap(0) { reserve(n); }
	array(const array& o) : ptr(0), size(0), cap(0) {
		reserve(o.size);
		for(U64 i = 0; i < o.size; ++i) new(ptr + i) T(o.ptr[i]);
		size = o.size;
	}
	array(array&& o) noexcept : ptr(o.ptr), size(o.size), cap(o.cap) {
		o.ptr = 0;
		o.size = 0;
		o.cap = 0;
	}
	~array() {
		clear();
		free(ptr);
	}

	array& operator=(const array& o) {
		if(this == &o) return *this;
		clear();
		reserve(o.size);
		for(U64 i = 0; i < o.size; ++i) new(ptr + i) T(o.ptr[i]);
		size = o.size;
		return *this;
	}

	array& operator=(array&& o) noexcept {
		if(this == &o) return *this;
		clear();
		free(ptr);
		ptr = o.ptr;
		size = o.size;
		cap = o.cap;
		o.ptr = 0;
		o.size = 0;
		o.cap = 0;
		return *this;
	}

	void reserve(U64 n) {
		if(n <= cap) return;
		U64 nc = cap ? cap * 2 : 8;
		if(nc < n) nc = n;
		T* np = (T*)malloc(nc * sizeof(T));
		for(U64 i = 0; i < size; ++i) {
			new(np + i) T((T&&)ptr[i]);
			ptr[i].~T();
		}
		free(ptr);
		ptr = np;
		cap = nc;
	}

	void resize(U64 n) {
		if(n < size) {
			for(U64 i = n; i < size; ++i) ptr[i].~T();
		} else {
			reserve(n);
			for(U64 i = size; i < n; ++i) new(ptr + i) T();
		}
		size = n;
	}

	void push(const T& v) {
		reserve(size + 1);
		new(ptr + size) T(v);
		++size;
	}
	void push(T&& v) {
		reserve(size + 1);
		new(ptr + size) T((T&&)v);
		++size;
	}
	void pop() {
		if(size) {
			--size;
			ptr[size].~T();
		}
	}

	void clear() {
		for(U64 i = 0; i < size; ++i) ptr[i].~T();
		size = 0;
	}

	T& operator[](U64 i) { return ptr[i]; }
	const T& operator[](U64 i) const { return ptr[i]; }

	T* begin() { return ptr; }
	T* end() { return ptr + size; }
	const T* begin() const { return ptr; }
	const T* end() const { return ptr + size; }

	slice<T> get_slice() { return slice<T>(ptr, size); }
	slice<T> get_slice(U64 s, U64 e) { return slice<T>(ptr + s, e - s); }
	const slice<T> get_slice() const { return slice<T>(ptr, size); }
	const slice<T> get_slice(U64 s, U64 e) const {
		return slice<T>(ptr + s, e - s);
	}

	T* ptr;
	U64 size;
	U64 cap;
};

#endif // #ifndef UTL_arr_H