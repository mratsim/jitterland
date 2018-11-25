# For now only working on POSIX
# for windows use VirtualAlloc, VirtualProtect, VrtualFree

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
  # Special use of registers: https://stackoverflow.com/questions/36529449/why-are-rbp-and-rsp-called-general-purpose-registers/51347294#51347294
  rax = 0b0_000
  rcx = 0b0_001
  rdx = 0b0_010
  rbx = 0b0_011
  rsp = 0b0_100  # Stack pointer
  rbp = 0b0_101
  rsi = 0b0_110
  rdi = 0b0_111
  r8  = 0b1_000
  r9  = 0b1_001
  r10 = 0b1_010
  r11 = 0b1_011
  r12 = 0b1_100
  r13 = 0b1_101
  r14 = 0b1_110
  r15 = 0b1_111

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
#     Important, using RSP or R12 (stack pointer regs), will use SIB instead of RM
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

proc modrm(adr_mode: AddressingMode, reg_rm: Reg, b: static bool): byte =
  when not b: # Only keep the last 3-bit if not extended
    let reg_rm = reg_rm.byte and 0b111
  result =           adr_mode.byte shl 6
  result = result or   reg_rm.byte

proc modrm(adr_mode: AddressingMode, reg_ref: Reg, r: static bool, reg_rm: Reg, b: static bool): byte =
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

proc mov(reg: range[rax..rdi], imm32: uint32): array[7, byte] =
  ## Move immediate 32-bit value into register
  result[0]       = rex_prefix(w = true, r = false, x = true, b = false)
  result[1]       = 0xC7
  result[2]       = modrm(Direct, reg, false)
  result[3 ..< 7] = cast[array[4, byte]](imm32) # We assume that imm32 is little-endian as we are jitting on x86

proc toHex(bytes: openarray[byte]): string =
  const hexChars = "0123456789abcdef"

  result = newString(3 * bytes.len)
  for i in 0 ..< bytes.len:
    result[3*i  ] = hexChars[int bytes[i] shr 4 and 0xF]
    result[3*i+1] = hexChars[int bytes[i]       and 0xF]
    result[3*i+2] = ' '

when isMainModule:
  let a = allocJitMem()
  echo a.repr

  echo mov(rax, 1).toHex
  echo mov(rdi, 1).toHex
