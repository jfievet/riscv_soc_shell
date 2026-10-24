@echo off
REM Batch script to compile main.c for PicoRV32 (RISC-V)

python gen_time_header.py

REM Set the path to your RISC-V GCC toolchain
set RISCV_GCC_PATH=C:\Tools\xpack-riscv-none-elf-gcc-15.2.0-1\bin

REM Set the compiler prefix
set RISCV_PREFIX=riscv-none-elf-

REM Compile main.c to main.elf
"%RISCV_GCC_PATH%\%RISCV_PREFIX%gcc.exe" -march=rv32i -mabi=ilp32 -mno-relax -Os -nostartfiles -T link.ld crt0.S main.c ..\common\common_lib.c -o main.elf
"%RISCV_GCC_PATH%\%RISCV_PREFIX%objdump.exe" -d main.elf > main.dis

REM Show size summary
"%RISCV_GCC_PATH%\%RISCV_PREFIX%size.exe" main.elf

REM Optional: Generate a hex file
"%RISCV_GCC_PATH%\%RISCV_PREFIX%objcopy.exe" -O ihex main.elf main.hex

echo Compilation finished.

python xilinx_hex_to_bytes.py

echo FPGA ram generated.