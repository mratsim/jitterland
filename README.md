# Jitterland

Playground for VMs and JIT

This is a playground for my experiments in VMs and JITs in Nim.

All the interpreters and JITs implement the [Brainfuck language](https://en.wikipedia.org/wiki/Brainfuck) and are run on several examples:

- A [commented Hello World](bf_hello.nim) from Wikipedia
- In [brainfuck_src](brainfuck_src)
  - A cpu-intensive mandelbrot fractal
  - An interactive integer factorization program
  - The Brainfuck benchmark used by Kostya for [programming language benchmarks](https://github.com/kostya/benchmarks) which prints the alphabet in reverse order

Available implementations:
  - [kostya_bf2.nim](kostya_bf2.nim) is the implementation from kostya's benchmark.
    It is a pure interpreter that processes the Brainfuck program in a single pass.
  - [bfVM_v01.nim](bfVM_v01.nim) implements a pure interpreter in 2 stages.
    - First lexing the program into an opcode stream,
    - Second executing with an optimized interpreter using computed gotos.
      Conditional jump targets are tracked via a stack and skip to for a forward jump.
  - [bfVM_v02.nim](bfVM_v02.nim) also implements a pure interpreter in 2 stages.
    - First lexing the program into an opcode stream,
      Additionally jump targets will be precomputed and stored into a sequence with the
      same size as the opcode stream. If a jump can occur, the target byte offset will be stored in the sequence at the index of the current opcode.
    - Second executing with an optimized interpreter using computed gotos.
  - [bfVM_v03_jit.nim](bfVM_v03_jit.nim) implements a written from scratch JIT for x86_64.
    - First the whole program is lexed and compiled to machine code without optimisation (no folding of multiple increments for example)
    - Second the machine code is run

A Hello World for a written-from-scratch x86-64 JIT is available in [jit_hello.nim](jit_hello.nim).
A mini JIT available as a library is available in the [jit folder](jit). It has been productionized in the [Laser library](https://github.com/numforge/laser) as [Photon JIT](https://github.com/numforge/laser/tree/master/laser/photon_jit)
