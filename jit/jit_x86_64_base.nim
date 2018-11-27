# License Apache v2
# Copyright 2018, Mamy André-Ratsimbazafy

import
  macros, tables,
  ./jit_datatypes

# ############################################################
#
#                    x86-64 Architecture
#
# ############################################################

type
  Reg_X86_64* = enum
    # AX in 16-bit, EAX in 32-bit, RAX in 64-bit
    # Registers are general purposes but some have specific uses for some instructions
    # Special use of registers: https://stackoverflow.com/questions/36529449/why-are-rbp-and-rsp-called-general-purpose-registers/51347294#51347294
    rAX = 0b0_000  # Accumulator
    rCX = 0b0_001  # Loop counter
    rDX = 0b0_010  # Extend accumulator precision
    rBX = 0b0_011  # Array index
    rSP = 0b0_100  # Stack pointer                            - In ModRM this triggers SIB addressing
    rBP = 0b0_101  # Stack base pointer (stack frame address) - In ModRM this triggers RIP addressing (instruction pointer relative) if mod = 0b00
    rSI = 0b0_110  # Source index for string operations
    rDI = 0b0_111  # Destination index for string operations
    r8  = 0b1_000
    r9  = 0b1_001
    r10 = 0b1_010
    r11 = 0b1_011
    r12 = 0b1_100  # In ModRM this triggers SIB addressing
    r13 = 0b1_101  # In ModRM on x86_64, this triggers RIP addressing (instruction pointer relative) if mod = 0b00
    r14 = 0b1_110
    r15 = 0b1_111

# ############################################################
#
#               x86-64 exported common routines
#
# ############################################################

type InstructionPointer* = object # Instruction pointer
const rIP* = InstructionPointer()

# Sources:
#    - https://www-user.tu-chemnitz.de/~heha/viewchm.php/hs/x86.chm/x64.htm
#    - https://www.slideshare.net/ennael/kr2014-x86instructions
#    - https://wiki.osdev.org/X86-64_Instruction_Encoding

# REX:                 0-1      byte
# Opcode:              1-3      byte(s)
# Mod R/M:             0-1      byte
# SIB:                 0-1      byte
# Displacement: 0, 1, 2, 4      byte(s)
# Immediate:    0, 1, 2, 4 or 8 byte(s)

func rex_prefix*(w, r, x, b: range[0..1] = 0): byte {.compileTime.}=
  ## w: true if a 64-bit operand size is used,
  ##    otherwise 0 for default operand size (usually 32 but some are 64-bit default)
  ## r: ModRM.reg = r.XXX i.e switch between rax 0.000 and r8 1.000
  ## x: SIB.index = x.XXX i.e. switch between rax 0.000 and r8 1.000
  ## b: ModRM.rm = b.XXX i.e. switch between rax 0.000 and r8 1.000
  result = 0b0100 shl 4
  result = result or (w.byte shl 3)
  result = result or (r.byte shl 2)
  result = result or (x.byte shl 1)
  result = result or b.byte

# ModRM (Mode-Register-Memory)
#   - Mod - 2-bit: addressing mode:
#                    - 0b11 - direct
#                    - 0b00 - RM
#                    - 0b01 - RM + 1-byte displacement
#                    - 0b10 - RM + 4-byte displacement
#     Important:
#       - using RSP or R12 (stack pointer register), will use SIB instead of RM
#       - using 0b00 + RBP or R13 (stack base pointer register), will use RIP+disp32 instead of RM
#         RIP addressing is only valid on x86_64
#     for addressing mode purposes
#   - Reg - 3-bit: register reference. Can be extended to 4 bits.
#   - RM  - 3-bit: register operand or indirect register operand. Can be extended to 4 bits.
#
#   7                           0
# +---+---+---+---+---+---+---+---+
# |  mod  |    reg    |     rm    |
# +---+---+---+---+---+---+---+---+

type AddressingMode_X86_64* = enum
  Indirect        = 0b00
  Indirect_disp8  = 0b01
  Indirect_disp32 = 0b10
  Direct          = 0b11

func modrm*(
      adr_mode: AddressingMode_X86_64,
      opcode_extension: range[0..15],
      rm: Reg_X86_64
    ): byte {.compileTime.}=
  let # Use complementary REX prefix to address the upper registers
    rm = rm.byte and 0b111
  result =         adr_mode.byte shl 6
  result = opcode_extension.byte shl 3
  result = result or     rm

func modrm*(
      adr_mode: AddressingMode_X86_64,
      reg, rm: Reg_X86_64
    ): byte {.compileTime.}=
  let # Use complementary REX prefix to address the upper registers
    reg = reg.byte and 0b111
    rm = rm.byte and 0b111
  result =           adr_mode.byte shl 6
  result = result or      reg.byte shl 3
  result = result or       rm.byte

# SIB (Scale-Index-Base)
#   Used in indirect addressing with displacement
#   - Scale - 2-bit: Scaling factor is 2^SIB.scale => 0b00 -> 1, 0b01 -> 2, 0b10 -> 4, 0b11 -> 8
#   - Index - 3-bit: Register holding the displacement
#   - Base  - 3-bit: Register holding the base address

#   7                           0
# +---+---+---+---+---+---+---+---+
# | scale |   index   |    base   |
# +---+---+---+---+---+---+---+---+

# ############################################################
#
#               x86-64 clobbered registers routines
#
# ############################################################

func push*(reg: range[rax..rdi]): byte {.compileTime.}=
  ## Push a register on the stack
  result = 0x50.byte or reg.byte

func pop*(reg: range[rax..rdi]): byte {.compileTime.}=
  ## Pop the stack into a register
  result = 0x58.byte or reg.byte

func push_ext*(reg: range[r8..r15]): array[2, byte] {.compileTime.}=
  ## Push an extended register on the stack
  result = [
      rex_prefix(b = 1),
      0x50.byte or (reg.byte and 0b111)
    ]

func pop_ext*(reg: range[r8..r15]): array[2, byte] {.compileTime.}=
  ## Pop the stack into an extended register
  result = [
      rex_prefix(b = 1),
      0x58.byte or (reg.byte and 0b111)
    ]

func saveRestoreRegs(dr: var DirtyRegs[Reg_X86_64]) {.compileTime.}=
  ## Generate the code to save and restore clobbered registers
  for reg in dr.clobbered_regs:
    if reg in rax..rdi:
      dr.save_regs.add push(reg)
      dr.restore_regs.add pop(reg)
    else:
      dr.save_regs.add push_ext(reg)
      dr.restore_regs.add pop_ext(reg)

# ############################################################
#
#               x86-64 code generation macros
#
# ############################################################

macro gen_x86_64*(
        assembler: untyped,
        clean_registers: static bool,
        body: untyped
      ): JitFunction =
  ## Initialise an Assembler for x86_64
  ## that will parse the code generation body and emit
  ## the corresponding code.
  ##
  ## Regular Nim code is allowed in the code generation section
  ## including control flow, loops, defining proc, templates,
  ## macros or variables.
  ##
  ## The following limitations apply:
  ##   - Do not alias the registers, i.e. const foo = rax
  ##   - Do not overload the registers, i.e. proc rax() = discard
  ##   - As the code is generated at the end of the codegen block
  ##     you should not return or break early of it.

  # First, parse the body to find registers referenced
  var dirty_regs: DirtyRegs[Reg_X86_64]
  dirty_regs.searchClobberedRegs body

  # Then create the bytecode to save and restore them
  dirty_regs.saveRestoreRegs()

  # Now initialize the assembler
  let
    saveRegs = newLit dirty_regs.save_regs
    restoreRegs = newLit dirty_regs.restore_regs

  let asm_init = block:
    if clean_registers:
      let clean_regs = newLit clean_registers
      quote do:
        var `assembler` = Assembler[Reg_X86_64](
                code: `saveRegs`,
                labels: initTable[Label, LabelInfo](),
                clean_regs: `clean_regs`,
                restore_regs: `restoreRegs`
        )
    else: quote do:
      var `assembler` = Assembler[Reg_X86_64](
              labels: initTable[Label, LabelInfo](),
              clean_regs: `clean_registers`
      )

  result = nnkBlockStmt.newTree(
    newEmptyNode(),
    nnkStmtList.newTree(
      asm_init,
      body,
      newCall(bindSym"post_process", assembler),
      newCall(bindSym"newJitFunction", assembler)
    )
  )
