# License Apache v2
# Copyright 2018, Mamy André-Ratsimbazafy

import
  ./jit_datatypes, ./jit_x86_64_base

func inc*(a: var Assembler[Reg_X86_64], reg: static Reg_X86_64) {.inline.} =
  ## Increment a register by 1
  ## Note that the Carry Flag is not updated
  ## in case of rollover
  const is_low_reg = reg in rax..rdi
  a.code.add [
    rex_prefix(w = 1),
    0xFF,
    modrm(Direct, opcode_extension = 0, rm = reg, not is_low_reg)
  ]

func dec*(a: var Assembler[Reg_X86_64], reg: static Reg_X86_64) {.inline.} =
  ## Decrement a register by 1
  ## Note that the Carry Flag is not updated
  ## in case of rollover
  const is_low_reg = reg in rax..rdi
  a.code.add [
    rex_prefix(w = 1),
    0xFF,
    modrm(Direct, opcode_extension = 1, rm = reg, not is_low_reg)
  ]

func inc*(a: var Assembler[Reg_X86_64], adr_reg: static array[1, Reg_X86_64]) {.inline.} =
  ## Increment the memory location pointed to by the register by 1
  ## Note that the Carry Flag is not updated
  ## in case of rollover
  const is_low_reg = adr_reg[0] in rax..rdi
  a.code.add [
    rex_prefix(w = 1),
    0xFF,
    modrm(Indirect, opcode_extension = 0, rm = adr_reg[0], not is_low_reg)
  ]

func dec*(a: var Assembler[Reg_X86_64], adr_reg: static array[1, Reg_X86_64]) {.inline.} =
  ## Decrement the memory location pointed to by the register by 1
  ## Note that the Carry Flag is not updated
  ## in case of rollover
  const is_low_reg = adr_reg[0] in rax..rdi
  a.code.add [
    rex_prefix(w = 1),
    0xFF,
    modrm(Indirect, opcode_extension = 1, rm = adr_reg[0], not is_low_reg)
  ]
