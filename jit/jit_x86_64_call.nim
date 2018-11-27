# License Apache v2
# Copyright 2018, Mamy André-Ratsimbazafy

import
  ./jit_datatypes, ./jit_x86_64_base

func syscall*(a: var Assembler[Reg_X86_64]) {.inline.}=
  ## Syscall opcode
  ## `rax` will determine which syscall is called.
  ##   - Write syscall (0x01 on Linux, 0x02000004 on OSX):
  ##       - os.write(rdi, rsi, rdx) equivalent to
  ##       - os.write(file_descriptor, str_pointer, str_length)
  ##       - The file descriptor for stdout is 0x01
  a.code.add [byte 0x0f, 0x05]

func ret*(a: var Assembler[Reg_X86_64]) {.inline.}=
  ## Return from function opcode
  ## If the assembler autocleans the clobbered registers
  ## this will restore them to their previous state
  if a.clean_regs:
    a.code.add a.restore_regs
  a.code.add byte 0xC3
