# Brainfuck interpreter (and JITer?)

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

func skip(vm: var BrainfuckVM) =
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

proc executeOpcodes(vm: var BrainfuckVM) =
  when defined(vmTrace):
    echo vm.code
  while true:
    {.computedGoto.}
    when defined(vmTrace):
      stdout.write &"\nBefore - pc: {vm.pc:>03}, op: {vm.code[vm.pc]:<6}, I: {vm.I:>04}, mem: {vm.mem[vm.I]:>03}, stack: {vm.stack:<015}"
    case vm.next():
    of opINCP: inc vm.I
    of opDECP: dec vm.I
    of opINCA: inc vm.mem[vm.I]
    of opDECA: dec vm.mem[vm.I]
    of opDUMP: stdout.write cast[char](vm.mem[vm.I])
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
      echo "\nDONE!"
      break
    when defined(vmTrace):
      stdout.write &"-   After - pc: {vm.pc:>03}, op: {vm.code[vm.pc]:<6}, I: {vm.I:>04}, mem: {vm.mem[vm.I]:>03}, stack: {vm.stack:<015}"

when isMainModule:

  # Hello world
  let prog =  """
              [ This program prints "Hello World!" and a newline to the screen, its
                length is 106 active command characters. [It is not the shortest.]

                This loop is an "initial comment loop", a simple way of adding a comment
                to a BF program such that you don't have to worry about any command
                characters. Any ".", ",", "+", "-", "<" and ">" characters are simply
                ignored, the "[" and "]" characters just have to be balanced. This
                loop and the commands it contains are ignored because the current cell
                defaults to a value of 0; the 0 value causes this loop to be skipped.
              ]
              ++++++++               Set Cell #0 to 8
              [
                  >++++               Add 4 to Cell #1; this will always set Cell #1 to 4
                  [                   as the cell will be cleared by the loop
                      >++             Add 2 to Cell #2
                      >+++            Add 3 to Cell #3
                      >+++            Add 3 to Cell #4
                      >+              Add 1 to Cell #5
                      <<<<-           Decrement the loop counter in Cell #1
                  ]                   Loop till Cell #1 is zero; number of iterations is 4
                  >+                  Add 1 to Cell #2
                  >+                  Add 1 to Cell #3
                  >-                  Subtract 1 from Cell #4
                  >>+                 Add 1 to Cell #6
                  [<]                 Move back to the first zero cell you find; this will
                                      be Cell #1 which was cleared by the previous loop
                  <-                  Decrement the loop Counter in Cell #0
              ]                       Loop till Cell #0 is zero; number of iterations is 8

              The result of this is:
              Cell No :   0   1   2   3   4   5   6
              Contents:   0   0  72 104  88  32   8
              Pointer :   ^

              >>.                     Cell #2 has value 72 which is 'H'
              >---.                   Subtract 3 from Cell #3 to get 101 which is 'e'
              +++++++..+++.           Likewise for 'llo' from Cell #3
              >>.                     Cell #5 is 32 for the space
              <-.                     Subtract 1 from Cell #4 for 87 to give a 'W'
              <.                      Cell #3 was set to 'o' from the end of 'Hello'
              +++.------.--------.    Cell #3 for 'rl' and 'd'
              >>+.                    Add 1 to Cell #5 gives us an exclamation point
              >++.                    And finally a newline from Cell #6
              """
  let s = prog.newStringStream()

  var vm = s.initBrainfuckVM()
  vm.executeOpcodes()
