# License Apache v2
# Copyright 2018, Mamy André-Ratsimbazafy

func round_step_up*(x: Natural, step: static Natural): int {.inline.} =
  ## Round the input to the next multiple of "step"
  when (step and (step - 1)) == 0:
    # Step is a power of 2. (If compiler cannot prove that x>0 it does not make the optim)
    result = (x + step - 1) and not(step - 1)
  else:
    result = ((x + step - 1) div step) * step

func `&`*[N1, N2: static[int], T](
    a: array[N1, T],
    b: array[N2, T]
    ): array[N1 + N2, T] {.inline.}=
  ## Array concatenation
  result[0 ..< N1] = a
  result[N1 ..< result.len] = b
