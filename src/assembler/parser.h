#ifndef PARSER_H
#define PARSER_H

#include "tokenizer.h"

namespace so {
	struct parser {
		static auto parse(const str& source) -> arr<inst>;
	};
} // namespace so

#endif // #ifndef PARSER_H
