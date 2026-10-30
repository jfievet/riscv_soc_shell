/* AXI SoC Subsystem — Application linker script
 *
 * Memory partition:
 *   Bootloader : 0x0000_0000 .. 0x0000_0FFF (4 KiB)
 *   Application: starts at 0x0050_0000 .. 0x00CF_FFFF (8 MB)
 */

ENTRY(_start)

RAM_ORIGIN = 0x00500000;
RAM_LENGTH = 0x00800000;   /* 8 MB reserved for the Application */

APP_ORIGIN = RAM_ORIGIN + RAM_LENGTH;

/* MMIO windows */
UART_BASE = 0x00100000;
GPIO_BASE = 0x00200000;
RESV_BASE = 0x00300000;

MEMORY
{
  RAM (rwx) : ORIGIN = RAM_ORIGIN, LENGTH = RAM_LENGTH
}

PHDRS
{
  text PT_LOAD FLAGS(5);   /* R | X */
  data PT_LOAD FLAGS(6);   /* R | W */
}

/* The Application stack remains inside the Application partition. */
_estack = ORIGIN(RAM) + LENGTH(RAM);

PROVIDE(__UART_BASE = UART_BASE);
PROVIDE(__GPIO_BASE = GPIO_BASE);
PROVIDE(__RESV_BASE = RESV_BASE);

PROVIDE(__Application_ORIGIN = RAM_ORIGIN);
PROVIDE(__Application_LENGTH = RAM_LENGTH);
PROVIDE(__APPLICATION_ORIGIN = APP_ORIGIN);

SECTIONS
{
  . = ORIGIN(RAM);
  __image_start__ = .;

  .text : ALIGN(4)
  {
    KEEP(*(.vectors))
    KEEP(*(.init))
    *(.text .text.*)
    *(.rodata .rodata.*)
  } > RAM :text

  .data : ALIGN(4)
  {
    __data_start__ = .;
    *(.data .data.*)
    __data_end__ = .;
  } > RAM :data

  .sdata : ALIGN(4)
  {
    __sdata_start__ = .;
    *(.sdata .sdata.*)
    *(.srodata .srodata.*)
    __sdata_end__ = .;
  } > RAM :data

  .bss (NOLOAD) : ALIGN(4)
  {
    __bss_start__ = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    __bss_end__ = .;
  } > RAM :data

  . = ALIGN(8);
  __image_end__ = .;
  _end = .;
  PROVIDE(end = .);

  __heap_start__ = .;
  __heap_end__ = _estack;

  PROVIDE(__global_pointer$ = ORIGIN(RAM) + 0x800);
  PROVIDE(__bss_start = __bss_start__);
  PROVIDE(__bss_end = __bss_end__);
  PROVIDE(__stack_top = _estack);

  /DISCARD/ :
  {
    *(.comment)
    *(.note .note.*)
  }
}

ASSERT(__image_end__ <= _estack,
       "Application too large: it overlaps the application partition");
