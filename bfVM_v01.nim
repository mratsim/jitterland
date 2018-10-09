# Brainfuck interpreter baseline

import streams

when defined(vmTrace):
  import strformat

type
  BfOpKind = enum
    opINCP   # Increment pointer
    opDECP   # Decrement pointer
    opINCA   # Increment byte at pointer address
    opDECA   # Increment byte at pointer address
    opDUMP   # Print byte
    opSTOR   # Store byte at pointer address
    opJZ     # Jump if zero
    opBNZ    # Backtrack if not zero
    opHALT   # End of instructions

  BrainfuckVM = object
    code: seq[BfOpKind] # Operations
    pc: int             # Program counter: Address of the current instruction
    mem: seq[uint8]     # Memory
    I: int              # Memory address register
    stack: seq[int]     # Return stack for `[`

const MemSize = 30000   # Initial memory of the VM

proc lexBrainFuck(result: var seq[BfOpKind], stream: Stream) =
  while not stream.atEnd():
    case stream.readChar()
    of '>': result.add opINCP
    of '<': result.add opDECP
    of '+': result.add opINCA
    of '-': result.add opDECA
    of '.': result.add opDUMP
    of ',': result.add opSTOR
    of '[': result.add opJZ
    of ']': result.add opBNZ
    else: discard

proc initBrainfuckVM(s: Stream): BrainfuckVM =
  result.code.lexBrainFuck s
  result.mem = newSeq[uint8](MemSize)

func next(vm: var BrainfuckVM): BfOpKind {.inline.}=
  if vm.pc == vm.code.len:
    return opHALT
  result = vm.code[vm.pc]
  inc vm.pc

func skip(vm: var BrainfuckVM) {.inline.}=
  ## Looking for the `]` at the same level
  ## And set the program counter just after
  var bnzSkip = 0
  while true:
    case vm.next():
    of opJZ: inc bnzSkip
    of opBNZ:
      if bnzSkip == 0:
        break
      else:
        dec bnzSkip
    else:
      discard

when defined(vmTrace):
  proc traceBefore(vm: BrainfuckVM) =
    # Need to be separated, the if/else interferes with computed goto labels
    if vm.pc < vm.code.len:
      stdout.write &"\nBefore - pc: {vm.pc:>03}, op: {vm.code[vm.pc]:<6}, I: {vm.I:>04}, mem: {vm.mem[vm.I]:>03}, stack: {vm.stack:<015}"
    else:
      stdout.write "Before - No code left, end of execution"

  proc traceAfter(vm: BrainfuckVM) =
    # Need to be separated, the if/else interferes with computed goto labels
    if vm.pc < vm.code.len:
      stdout.write &"-   After - pc: {vm.pc:>03}, op: {vm.code[vm.pc]:<6}, I: {vm.I:>04}, mem: {vm.mem[vm.I]:>03}, stack: {vm.stack:<015}"
    else:
      stdout.write "-   After - No code left, end of execution"

proc executeOpcodes(vm: var BrainfuckVM) =
  when defined(vmTrace):
    echo vm.code
  while true:
    {.computedGoto.}
    when defined(vmTrace):
      vm.traceBefore()
    case vm.next():
    of opINCP: inc vm.I
    of opDECP: dec vm.I
    of opINCA: inc vm.mem[vm.I]
    of opDECA: dec vm.mem[vm.I]
    of opDUMP:
      stdout.write cast[char](vm.mem[vm.I])
      flushFile(stdout)
    of opSTOR: discard stdin.readBytes(vm.mem, vm.I, 1)
    of opJZ:
      if vm.mem[vm.I] == 0:
        vm.skip()
      else:
        vm.stack.add vm.pc
    of opBNZ:
      if vm.mem[vm.I] != 0:
        vm.pc = vm.stack[^1]
      else:
        discard vm.stack.pop()
    of opHALT:
      break
    when defined(vmTrace):
      vm.traceAfter()

proc execBFfile*(file: string) =
  let s = openFileStream(file)
  defer: s.close()
  var vm = s.initBrainfuckVM()
  vm.executeOpcodes()

proc execBFstring*(prog: string) =
  let s = newStringStream(prog)
  defer: s.close()
  var vm = s.initBrainfuckVM()
  vm.executeOpcodes()
