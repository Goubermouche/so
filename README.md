## sup [wip]
Instruction superoptimizer accelerated with CUDA.
## build
```
nix-shell
./build
./out/sup
```
## benchmarks
Currently gathered by `./out/sup ./test/addmul.s -e rv32i, rv32m`.
| GPU      | Enumerate (cand/sec) | Filter (cand/sec) |
|----------|----------------------|-------------------|
| GTX 1070 | 312M                 | 350M              |
## resources
- [**riscv-opcodes**](https://github.com/riscv/riscv-opcodes)
- [**HieraSynth**](https://dl.acm.org/doi/10.1145/3763162)
- [**Souper**](https://arxiv.org/abs/1711.04422)
- [**CEGIS**](https://arxiv.org/abs/1505.03953)
