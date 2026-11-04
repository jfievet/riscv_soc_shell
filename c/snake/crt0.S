.section .text
.global _start
_start:
  /* Set up stack pointer from linker symbol */
  la sp, __stack_top

  /* Zero .bss */
  la t0, __bss_start
  la t1, __bss_end
1:
  bgeu t0, t1, 2f
  sw zero, 0(t0)
  addi t0, t0, 4
  j 1b
2:
  /* Optionally initialize gp from linker symbol */
  la gp, __global_pointer$

  /* Jump to main */
  call main

  /* If main returns, loop forever */
3:
  j 3b
