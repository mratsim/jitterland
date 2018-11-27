# License Apache v2
# Copyright 2018, Mamy André-Ratsimbazafy

import jit_datatypes
export JitFunction, Label, Assembler, call, hash, label

import jit_x86_64_base
export Reg_X86_64, gen_x86_64

import
  jit_x86_64_call, jit_x86_64_load_store, jit_x86_64_raw_data,
  jit_x86_64_scalar_arith, jit_x86_64_stack
export
  jit_x86_64_call, jit_x86_64_load_store, jit_x86_64_raw_data,
  jit_x86_64_scalar_arith, jit_x86_64_stack

func toHex*(bytes: openarray[byte]): string =
  const hexChars = "0123456789abcdef"

  result = newString(3 * bytes.len)
  for i in 0 ..< bytes.len:
    result[3*i  ] = hexChars[int bytes[i] shr 4 and 0xF]
    result[3*i+1] = hexChars[int bytes[i]       and 0xF]
    result[3*i+2] = ' '
