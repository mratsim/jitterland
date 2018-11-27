# License Apache v2
# Copyright 2018, Mamy André-Ratsimbazafy

import
  ./jit_datatypes, ./jit_x86_64_base

# Push and Pop for registers are defined in "jit_x86_64_base"
# as they are needed for function cleanup.

func push*(a: var Assembler[Reg_X86_64], reg: static Reg_X86_64) {.inline.}=
  ## Push a register on the stack
  when reg in rax .. rdi:
    a.code.add push(reg)
  else:
    a.code.add push_ext(reg)

func pop*(a: var Assembler[Reg_X86_64], reg: static Reg_X86_64) {.inline.}=
  ## Pop the stack into a register
  when reg in rax .. rdi:
    a.code.add push(reg)
  else:
    a.code.add push_ext(reg)
