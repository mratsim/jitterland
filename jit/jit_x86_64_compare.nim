# License Apache v2
# Copyright 2018, Mamy André-Ratsimbazafy

import
  ./jit_datatypes, ./jit_x86_64_base

func cmp*(a: var Assembler[Reg_X86_64], adr_reg: static array[1, Reg_X86_64], imm8: uint8) {.inline.} =
  ## Compare byte at memory location pointed to by adr_reg with an immediate uint8
  when adr_reg[0] in rax .. rdi:
    a.code.add [
      byte 0x80,
      modrm(Indirect, opcode_extension = 7, rm = adr_reg[0])
    ]
  else:
    a.code.add [
      rex_prefix(b = 1),
      byte 0x80,
      modrm(Indirect, opcode_extension = 7, rm = adr_reg[0])
    ]
