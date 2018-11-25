# Array concatenation

func `&`*[N1, N2: static[int], T](
    a: array[N1, T],
    b: array[N2, T]
    ): array[N1 + N2, T] {.inline, noInit.}=
  ## Array concatenation
  result[0 ..< N1] = a
  result[N1 ..< result.len] = b

# ########################################################

# For now only working on POSIX
# for windows use VirtualAlloc, VirtualProtect, VirtualFree

# See - https://github.com/nim-lang/Nim/blob/devel/lib/system/osalloc.nix
const PageSize = 4096

when not defined(posix):
  {.fatal: "Only POSIX systems are supported".}

type MemProt {.size: cint.sizeof.}= enum
  ProtNone  = 0 # Page cannot be accessed
  ProtRead  = 1 # Page can be read
  ProtWrite = 2 # Page can be written
  ProtExec  = 4 # Page can be executed

when defined(osx) or defined(ios) or defined(bsd):
  # Note: MacOS and Iphone uses MAP_ANON instead of MAP_ANONYMOUS
  # They also define MAP_JIT= 0x0800
  type MemMap {.size: cint.sizeof.}= enum
    MapPrivate = 0x02       # Changes are private
    MapAnonymous = 0x1000   # Don't use a file
elif defined(solaris):
  type MemMap {.size: cint.sizeof.}= enum
    MapPrivate = 0x02
    MapAnonymous = 0x100
elif defined(haiku):
  type MemMap {.size: cint.sizeof.}= enum
    MapPrivate = 0x02
    MapAnonymous = 0x08
else: # ASM-Generic
  # Note, Nim splits linux x86-64 and the rest
  # This is at least valid on Android ARM
  # unsure about MIPS and co
  type MemMap {.size: cint.sizeof.}= enum
    MapPrivate = 0x02
    MapAnonymous = 0x20

type Flag[E: enum] = distinct cint

func flag[E: enum](e: varargs[E]): Flag[E] {.inline.} =
  ## Enum should only have power of 2 fields
  # Unfortunately iterating on low(E)..high(E)
  # will also iterate on the holes
  # static:
  #   for val in low(E)..high(E):
  #     assert (ord(val) and (ord(val) - 1)) == 0, "Enum values should all be power of 2, found " &
  #                                                 $val & " with value " & $ord(val) & "."
  var flags = 0
  for val in e:
    flags = flags or ord(val)
  result = Flag[E](flags)

when not defined(release):
  block:
    var DebugMapPrivate {.importc: "MAP_PRIVATE", header: "<sys/mman.h>".}: cint
    var DebugMapAnonymous {.importc: "MAP_ANONYMOUS", header: "<sys/mman.h>".}: cint

    assert ord(MapPrivate) == DebugMapPrivate, "Your CPU+OS platform is misconfigured"
    assert ord(MapAnonymous) == DebugMapAnonymous, "Your CPU+OS platform is misconfigured"
    echo "MemMapping constants success"

proc mmap(
    adr: pointer, len: int,
    prot: Flag[MemProt], flags: Flag[MemMap],
    file_descriptor: cint, # -1 for anonymous memory
    offset: cint           # Offset in the file descriptor, PageSize aligned. Return Offset
  ): pointer {.header: "<sys/mman.h>", sideeffect.}
  ## The only portable address adr is "nil" to let OS decide
  ## where to alloc
  ## Returns -1 if error

proc mprotect(adr: pointer, len: int, prot: Flag[MemProt]) {.header: "<sys/mman.h>", sideeffect.}
  ## len should be a multiple of PageSize
  ## replace previously existing protection with a set of new ones
  ## If an access is disallowed, program will segfault

proc munmap(adr: pointer, len: int) {.header: "<sys/mman.h>", sideeffect.}

type JitMem[P: static set[MemProt]] = object
  # We don't use Flag[MemProt] for the static type
  # due to Nim limitation
  memaddr: pointer
  len: int

proc allocJitMem(): JitMem[{ProtRead, ProtWrite}] =
  result.memaddr = mmap(
            nil, PageSize,
            static(flag(ProtRead, ProtWrite)),
            static(flag(MapAnonymous, MapPrivate)),
            -1, 0
          )
  result.len = PageSize
  doAssert cast[int](result.memaddr) != -1, "mmap allocation failure"

proc `=destroy`[P: static set[MemProt]](jitmem: var JitMem[P]) =
  if jitmem.memaddr != nil:
    munmap(jitmem.memaddr, jitmem.len)

type Reg = enum
  # AX in 16-bit, EAX in 32-bit, RAX in 64-bit
  # Registers are general purposes but some have specific euse
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
  r13 = 0b1_101  # In ModRM this triggers RIP addressing (instruction pointer relative) if mod = 0b00
  r14 = 0b1_110
  r15 = 0b1_111

type InstructionPointer = object # Instruction pointer
const rIP = InstructionPointer()

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

func rex_prefix(w, r, x, b: static bool): byte =
  ## w: true if a 64-bit operand size is used,
  ##    otherwise 0 for default operand size (usually 32 but some are 64-bit default)
  ## r: if true: extend ModRM.reg from 3-bit to 4-bit
  ## x: if true: extend SIB.index (Scale-Index-Base)
  ## b: if true: extend ModRM.rm from 3-bit to 4-bit
  result = 0b0100 shl 4
  result = result or (w.byte shl 3)
  result = result or (r.byte shl 2)
  result = result or (x.byte shl 1)
  result = result or (b.byte)

  assert 0x40.byte <= result and result <= 0x4f, "REX prefix issue"

# ModRM (Mode-Register-Memory)
#   - Mod - 2-bit: addressing mode:
#                    - 0b11 - direct
#                    - 0b00 - RM
#                    - 0b01 - RM + 1-byte displacement
#                    - 0b10 - RM + 4-byte displacement
#     Important:
#       - using RSP or R12 (stack pointer register), will use SIB instead of RM
#       - using 0b00 + RBP or R13 (stack base pointer register), will use RIP+disp32 instead of RM
#     for addressing mode purposes
#   - Reg - 3-bit: register reference. Can be extended to 4 bits.
#   - RM  - 3-bit: register operand or indirect register operand. Can be extended to 4 bits.
#
#   7                           0
# +---+---+---+---+---+---+---+---+
# |  mod  |    reg    |     rm    |
# +---+---+---+---+---+---+---+---+

type AddressingMode = enum
  Indirect        = 0b00
  Indirect_disp8  = 0b01
  Indirect_disp32 = 0b10
  Direct          = 0b11

func modrm(adr_mode: AddressingMode, reg_rm: Reg, b: static bool): byte =
  when not b: # Only keep the last 3-bit if not extended
    let reg_rm = reg_rm.byte and 0b111
  result =           adr_mode.byte shl 6
  result = result or   reg_rm.byte

func modrm(adr_mode: AddressingMode, reg_ref: Reg, r: static bool, reg_rm: Reg, b: static bool): byte =
  when not r: # Only keep the last 3-bit if not extended
    let reg_ref = reg_ref.byte and 0b111
  when not b:
    let reg_rm = reg_rm.byte and 0b111
  result =           adr_mode.byte shl 6
  result = result or  reg_ref.byte shl 3
  result = result or   reg_rm.byte

# SIB (Scale-Index-Base)
#   Used in indirect addressing with displacement
#   - Scale - 2-bit: Scaling factor is 2^SIB.scale => 0b00 -> 1, 0b01 -> 2, 0b10 -> 4, 0b11 -> 8
#   - Index - 3-bit: Register holding the displacement
#   - Base  - 3-bit: Register holding the base address

#   7                           0
# +---+---+---+---+---+---+---+---+
# | scale |   index   |    base   |
# +---+---+---+---+---+---+---+---+

func mov(reg: static range[rax..rdi], imm32: uint32): array[7, byte] =
  ## Move immediate 32-bit value into register
  result[0]       = rex_prefix(w = true, r = false, x = false, b = false)
  result[1]       = 0xC7
  result[2]       = modrm(Direct, reg, false)
  result[3 ..< 7] = cast[array[4, byte]](imm32) # We assume that imm32 is little-endian as we are jitting on x86

func mov(dst, src: static range[rax..rdi]): array[3, byte] =
  ## Move 64-bit content from register to register
  result[0] = rex_prefix(w = true, r = false, x = false, b = false)
  result[1] = 0x89
  result[2] = modrm(Direct, src, false, dst, false)

func lea(dst: static range[rax..rdi], src: static InstructionPointer, disp32: uint32): array[7, byte] =
  ## Load an effective address relative to the instruction pointer
  ## Effective address = Current instruction + 32-bit displacement
  result[0]       = rex_prefix(w = true, r = false, x = false, b = false)
  result[1]       = 0x8D
  result[2]       = modrm(Indirect, dst, false, rbp, false) # To use rip, modrm requires passing "Indirect" (0b00) + RBP
  result[3 ..< 7] = cast[array[4, byte]](disp32)            # We assume that imm32 is little-endian as we are jitting on x86

func syscall(): array[2, byte] = [byte 0x0f, 0x05]
func ret(): array[1, byte] = [byte 0xc3]

# TODO: clobbered register autodetection
func push(reg: static range[rax..rdi]): array[1, byte] =
  ## Push a register on the stack
  result[0] = 0x50.byte or reg.byte

func pop(reg: static range[rax..rdi]): array[1, byte] =
  ## Pop the stack into a register
  result[0] = 0x58.byte or reg.byte

func pushStackFrame(): array[4, byte] =
  result[0]      = push(rbp)[0]
  result[1 .. 3] = mov(rbp, rsp)

func popStackFrame(): array[1, byte] =
  # TODO optimization if rsp == rbp
  # Leave is equivalent to (Intel syntax - mov dst, src)
  # - mov rbp, rsp
  # - pop rbp
  # If rsp == rbp, we can just pop rbp
  result[0] = 0xC9 # Leave

func toHex(bytes: openarray[byte]): string =
  const hexChars = "0123456789abcdef"

  result = newString(3 * bytes.len)
  for i in 0 ..< bytes.len:
    result[3*i  ] = hexChars[int bytes[i] shr 4 and 0xF]
    result[3*i+1] = hexChars[int bytes[i]       and 0xF]
    result[3*i+2] = ' '

import sequtils, os
proc main() =
  const HelloWorld = mapLiterals(['H','e','l','l','o',' ','W','o','r','l','d','!'], byte)
  let jitmem = allocJitMem()
  defer: munmap(jitmem.memaddr, jitmem.len)

  ##############################################
  # 1. Writing the instruction to the JIT memory
  # 1.1. The OS "write" system call
  when defined(linux):
    let instr_write_func = mov(rax, 0x01)
  elif defined(osx):
    let instr_write_func = mov(rax, 0x02000004)

  # Ordering:
  #   1. storing write system call address
  #   2. storing the location of the string to write to stdout
  #      this will be stored in the JIT part and so depends on the next steps
  #   3. storing the length of the string
  #   4. syscall
  #   5. Restoring registers for the caller
  #   6. return from syscall
  #   7. "Hello, World!"

  # 1.2. Hello world length and location offset
  let instr_hello_len = mov(rdx, HelloWorld.len)
  #      Offset is equal to length of instructions of step 3, 4 + restoring the 4 registers (5) + 6
  let instr_hello_ptr = lea(rsi, rip, instr_hello_len.len + syscall().len + 4 + ret().len)

  # 1.3. Storing the instructions
  let p = cast[ptr UncheckedArray[byte]](jitmem.memaddr)
  var pos = 0

  proc write_instr[N: static int](p: ptr UncheckedArray[byte], pos: var int, instr: array[N, byte]) {.sideeffect.} =
    for i in 0 ..< N:
      p[pos] = instr[i]
      inc pos

  # We are clobbering registers RAX, RDX an RSI
  # So we need to save (push) and restore (pop) them

  p.write_instr(pos, push(rax))
  p.write_instr(pos, push(rdi))
  p.write_instr(pos, push(rdx))
  p.write_instr(pos, push(rsi))

  p.write_instr(pos, instr_write_func) # rax = write syscall
  p.write_instr(pos, mov(rdi, 0x01))   # rdi = stdout (stdout file descriptor = 0x01)
  p.write_instr(pos, instr_hello_ptr)  # rsi = ptr to HelloWorld
  p.write_instr(pos, instr_hello_len)  # rdx = HelloWorld.len
  p.write_instr(pos, syscall())        # os_write(rdi, rsi, rdx)

  p.write_instr(pos, pop(rsi))
  p.write_instr(pos, pop(rdx))
  p.write_instr(pos, pop(rdi))
  p.write_instr(pos, pop(rax))
  p.write_instr(pos, ret())
  p.write_instr(pos, HelloWorld)

  #####################################################
  # 3. Sanity check

  echo "\n## JIT code expected"
  echo pushStackFrame().toHex
  echo instr_write_func.toHex
  echo instr_hello_ptr.toHex
  echo instr_hello_len.toHex
  echo syscall().toHex
  echo popStackFrame().toHex
  echo ret().toHex
  echo HelloWorld.toHex

  echo "\n## JIT code stored"
  for i in 0 ..< pos:
    stdout.write [p[i]].toHex
  echo ""

  #####################################################
  # 2. Changing permission from Read/Write to Read/Exec
  mprotect(jitmem.memaddr, jitmem.len, flag(ProtRead, ProtExec))

  #####################################################
  # 3. Execution
  let hello_jit = cast[proc(){.cdecl.}](jitmem.memaddr)
  echo "\n## JIT result"
  hello_jit()
  echo '\n'

when isMainModule:
  main()

