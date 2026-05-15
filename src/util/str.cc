#include "str.h"

str str_make(u8* p, u64 n) {
	str s;
	s.str = p;
	s.size = n;
	return s;
}

str str_cstring(const char* c) {
	const char* p = c;
	while(*p) ++p;
	return str_make((u8*)c, (u64)(p - c));
}

b32 str_eq(str a, str b) {
	if(a.size != b.size) return false;
	return memcmp(a.str, b.str, a.size) == 0;
}

b32 str_eq_cstr(str a, const char* c) {
	for(u64 i = 0; i < a.size; ++i) {
		if(c[i] == '\0' || (char)a.str[i] != c[i]) return false;
	}
	return c[a.size] == '\0';
}

str str_copy(arena* a, str s) {
	u8* dst = push_array(a, u8, s.size);
	memcpy(dst, s.str, s.size);
	return str_make(dst, s.size);
}

str str_push_fmt(arena* a, const char* fmt, ...) {
	va_list ap;
	va_start(ap, fmt);
	va_list ap2;
	va_copy(ap2, ap);
	int n = vsnprintf(0, 0, fmt, ap);
	va_end(ap);
	ASSERT(n >= 0, "str_push_fmt: vsnprintf failed\n");
	u8* dst = push_array(a, u8, (u64)n + 1);
	vsnprintf((char*)dst, (u64)n + 1, fmt, ap2);
	va_end(ap2);
	return str_make(dst, (u64)n);
}

str str_pad_to_len(arena* a, str s, u8 pad, u64 target_len) {
	const u64 pad_len = (target_len > s.size) ? (target_len - s.size) : 0;
	u8* dst = push_array(a, u8, s.size + pad_len);
	memcpy(dst, s.str, s.size);
	if(pad_len) memset(dst + s.size, pad, pad_len);
	return str_make(dst, s.size + pad_len);
}

void str_list_push(arena* a, str_list* list, str s) {
	str_node* n = push_struct(a, str_node);
	n->next = 0;
	n->s = s;
	if(list->last) {
		list->last->next = n;
	} else {
		list->first = n;
	}
	list->last = n;
	list->node_count += 1;
	list->total_size += s.size;
}

void str_list_push_fmt(arena* a, str_list* list, const char* fmt, ...) {
	va_list ap;
	va_start(ap, fmt);
	va_list ap2;
	va_copy(ap2, ap);
	int n = vsnprintf(0, 0, fmt, ap);
	va_end(ap);
	ASSERT(n >= 0, "str_list_pushf: vsnprintf failed\n");
	u8* dst = push_array(a, u8, (u64)n + 1);
	vsnprintf((char*)dst, (u64)n + 1, fmt, ap2);
	va_end(ap2);
	str_list_push(a, list, str_make(dst, (u64)n));
}

str str_list_flatten(arena* a, str_list* list, str sep) {
	const u64 nseps = list->node_count > 0 ? list->node_count - 1 : 0;
	const u64 total = list->total_size + nseps * sep.size;
	u8* dst = push_array(a, u8, total + 1);
	u8* p = dst;
	for(str_node* n = list->first; n; n = n->next) {
		memcpy(p, n->s.str, n->s.size);
		p += n->s.size;
		if(n->next && sep.size) {
			memcpy(p, sep.str, sep.size);
			p += sep.size;
		}
	}
	*p = 0;
	return str_make(dst, total);
}