#ifndef PARSER_H
#define PARSER_H

#include "tokenizer.h"

namespace so {
	struct parser {
		static auto parse(const str& source) -> arr<inst>;
	private:
		static auto identifier_to_opcode(const str& ident) -> opcode;
	};
} // namespace so

#endif // #ifndef PARSER_H
