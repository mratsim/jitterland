# License Apache v2
# Copyright 2018, Mamy André-Ratsimbazafy

import
  ./jit_datatypes, ./jit_x86_64_base

func embed_raw_bytes*(a: var Assembler[Reg_X86_64], data: openarray[byte]){.inline.} =
  ## Append raw data in the code
  a.code.add data
