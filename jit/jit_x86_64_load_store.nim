# License Apache v2
# Copyright 2018, Mamy André-Ratsimbazafy

import
  ./jit_datatypes, ./jit_x86_64_base

func mov*(a: var Assembler[Reg_X86_64], reg: static range[rax..rdi], imm32: uint32) {.inline.} =
  ## Move immediate 32-bit value into register
  a.code.add static(0xB8.byte + reg.byte) # Move imm to r
  a.code.add cast[array[4, byte]](imm32)

func mov*(a: var Assembler[Reg_X86_64], reg: static range[rax..rdi], imm64: uint64) {.inline.} =
  ## Move immediate 64-bit value into register
  a.code.add static(0xB8.byte + reg.byte) # Move imm to r
  a.code.add cast[array[8, byte]](imm64)

func mov*(a: var Assembler[Reg_X86_64], dst, src: static range[rax..rdi]) =
  ## Copy 64-bit register content to another register
  a.code.add [
    rex_prefix(w = true, r = false, x = false, b = false),
    0x89, # Move reg to r/m
    modrm(Direct, reg = src, false, rm = dst, false)
  ]

func lea*(a: var Assembler[Reg_X86_64], reg: static range[rax..rdi], label: static Label) {.inline.} =
  ## Load effective Address of the target label into a register
  # We use RIP-relative addressing. This is x86_64 only and does not exist on x86.

  a.code.add [
    rex_prefix(w = true, r = false, x = false, b = false),
    0x8D, # Move reg to r/m
    modrm(Indirect, reg = reg, false, rm = rbp, false), # RBP triggers rip-relative addressing.
    0x00, 0x00, 0x00, 0x00 # Placeholder for target label
  ]
  a.add_target label

# ############################################################
#
#               Notes on lower than 32-bit loads
#
# ############################################################

#  Regarding 16-bit loads
#    - It only saves one byte as we would need the 0x66 16-bit mode prefix
#    - Partial register loads cause stalls (https://stackoverflow.com/questions/41573502/why-doesnt-gcc-use-partial-registers)
#      because 8 and 16-bit immediate are not zero-extended into the register
#      so the CPU must assume dependency with the underlying larger register.
#      There is no penalties for loading 32-bit immediate into a 64-bit registers,
#      those are always zero-extended
#
#  Regarding 8-bit loads:
#    - Only speific registers are available.
#    - While it does not need an extra prefix as there are dedicated opcodes
#      it still suffers from partial register load stalls.
