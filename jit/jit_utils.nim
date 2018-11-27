# License Apache v2
# Copyright 2018, Mamy André-Ratsimbazafy

func round_step_up*(x: Natural, step: static Natural): int {.inline.} =
  ## Round the input to the next multiple of "step"
  when (step and (step - 1)) == 0:
    # Step is a power of 2. (If compiler cannot prove that x>0 it does not make the optim)
    result = (x + step - 1) and not(step - 1)
  else:
    result = ((x + step - 1) div step) * step
