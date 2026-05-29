## adding new extensions:
- Add a new directory in `src/extensions` named after the extension
- In the extension directory, create `opcodes.def` defining the X-macro for your extension's opcodes (use other extensions for inspiration)
- In `src/cpu/instruction.cuh`:
  - `#include` the new `opcodes.def` file
  - Append the extension to `DatabaseExtensionList`, `DatabaseExtensionOpcodeList`
  - Add the extension to `cpu_InstructionDatabase_build_host`
- In `src/extensions/run.cuh`
  - Add `case`s to the appropriate sim function for your opcode class:
    - **`ext_run_inst_cheap`**: all cheap ALU ops (rv32i / rv64i style)
    - **`ext_run_inst_mul`**: multiply ops (class 1); also add the opcode to `ext_op_class`
    - **`ext_run_inst_div`**: divide / remainder ops (class 2); also add the opcode to `ext_op_class`
  - These functions are used by both the CPU interpreter (`ext_run_inst`) and the
    GPU filter kernel (`ext_run_inst_dispatch` via `filter.cu`), so a single addition covers both paths.
  - If your new instruction uses RI shape (immediate in operands[1], no rs1), add a
    special-case to `ext_run_inst` like the existing `lui` handling.
- In `src/extensions/smt.h`
  - add `case`s for your opcodes to the single `ext_smt` switch (the SMT model)
