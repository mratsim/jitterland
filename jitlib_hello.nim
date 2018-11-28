# License Apache v2
# Copyright 2018, Mamy André-Ratsimbazafy

# ########################################################

# Hello World using the jit library
import
  ./jit/jit_export,
  sequtils

proc main() =
  const HelloWorld = mapLiterals(['H','e','l','l','o',' ','W','o','r','l','d','!'], byte)

  let fn = gen_x86_64(assembler = a, clean_registers = true):
    # Initialize a label placeholder for the HelloWorld string data
    let L1 = initLabel()

    # "write" syscall
    # rax = write syscall (0x01 on Linux, 0x02000004 on OSX)
    # rdi = stdout (stdout file descriptor = 0x01)
    # rsi = ptr to HelloWorld
    # rdx = HelloWorld.len
    # os.write(rdi, rsi, rdx) // os.write(file_descriptor, str_pointer, str_length)
    when defined(linux):
      a.mov rax, 0x01
    elif defined(osx):
      a.mov rax, 0x02000004
    else:
      {.error: "Unsupported OS".}

    a.mov rdi, 0x01
    a.lea rsi, L1
    a.mov rdx, HelloWorld.len
    a.syscall()
    a.ret()
    a.label L1
    a.embed_raw_bytes HelloWorld

  fn.call()
  echo '\n'
main()
