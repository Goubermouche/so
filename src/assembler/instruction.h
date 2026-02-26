#ifndef INSTRUCTION_H
#define INSTRUCTION_H

namespace so {
	struct opcode {
	};

	struct operand {
	};

	struct inst {
		 opcode op;
		 operand operands[2];
	};
} // namespace so

#endif // #ifndef INSTRUCTION_H
