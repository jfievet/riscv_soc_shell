/* AXI SoC Subsystem memory map */
ENTRY(_start)

/* AXI RAM: 4 KB at 0x0000_0000 (fits in Slave0 window 0x0000_0000?0x0000_FFFF) */
RAM_ORIGIN  = 0x00000000;
RAM_LENGTH  = 0x00100000;   /* 64 KB */

/* MMIO windows (not for section placement; for symbol reference in C) */
UART_BASE   = 0x00100000;   /* Slave1 window */
GPIO_BASE   = 0x00200000;   /* Slave2 window */
RESV_BASE   = 0x00300000;   /* Slave3 window */

/* Define memory regions: single RAM (exec + data) */
MEMORY
{
  RAM (rwx) : ORIGIN = RAM_ORIGIN, LENGTH = RAM_LENGTH
}

/* Define program headers to avoid RWX warning */
PHDRS
{
  text PT_LOAD FLAGS(5);  /* R(4) | X(1) => RX */
  data PT_LOAD FLAGS(6);  /* R(4) | W(2) => RW */
}

/* Stack at end of RAM, grows down */
_estack       = RAM_ORIGIN + RAM_LENGTH;

/* Export MMIO base symbols */
PROVIDE(__UART_BASE = UART_BASE);
PROVIDE(__GPIO_BASE = GPIO_BASE);

/* Sections placement: everything in RAM */
/* Provide symbols expected by generic crt0 */
PROVIDE(__global_pointer$ = RAM_ORIGIN + 0x800);

SECTIONS
{
  .text : {
    KEEP(*(.vectors))      /* optional */
    KEEP(*(.init))         /* optional */
    *(.text .text.*)
    *(.rodata .rodata.*)
  } > RAM :text

  /* Initialized data in RAM (no ROM load here since single-RAM system) */
  .data : {
    __data_start__ = .;
    *(.data .data.*)
    __data_end__ = .;
  } > RAM :data

  /* Uninitialized data */
  .bss (NOLOAD) : {
    __bss_start__ = .;
    *(.bss .bss.*)
    *(COMMON)
    __bss_end__ = .;
  } > RAM :data

  /* Small data sections (optional) */
  .sdata : { *(.sdata .sdata.*) } > RAM :data

  /* Heap markers (optional; adjust if you use malloc) */
  __heap_start__ = ALIGN(8);
  __heap_end__   = _estack;

  /* Common end symbols */
  _end = .;
  PROVIDE(end = .);
  /* Aliases matching toolchain expectations */
  PROVIDE(__bss_start = __bss_start__);
  PROVIDE(__bss_end = __bss_end__);

  /* Alias stack symbol for startup */
  PROVIDE(__stack_top = _estack);
}