# License Apache v2
# Copyright 2018, Mamy André-Ratsimbazafy

import
  ./jit_datatypes, ./jit_x86_64_base

func jz*(a: var Assembler[Reg_X86_64], label: Label) {.inline.} =
  ## Jump to Label if Zero Flag is set.
  a.code.add [
    byte 0x0F, 0x84,
    0x00, 0x00, 0x00, 0x00 # Placeholder for target label
  ]
  a.add_target label

func jnz*(a: var Assembler[Reg_X86_64], label: Label) {.inline.} =
  ## Jump to Label if Zero Flag is not set.
  a.code.add [
    byte 0x0F, 0x85,
    0x00, 0x00, 0x00, 0x00 # Placeholder for target label
  ]
  a.add_target label
