@echo off
REM Batch script to compile bootload and app for PicoRV32 (RISC-V)

REM ------------------------------------------------------------------
REM -- Configuration
REM ------------------------------------------------------------------

set APP_DIR=axi_write_loopback

REM Set the path to your RISC-V GCC toolchain
set RISCV_GCC_PATH=C:\Tools\xpack-riscv-none-elf-gcc-15.2.0-1\bin

REM Set the compiler prefix
set RISCV_PREFIX=riscv-none-elf-


REM ------------------------------------------------------------------
REM -- BOOTLOADER
REM ------------------------------------------------------------------

cd ..
cd bootloader
python gen_time_header.py
cd..
cd bootloader_and_app

REM Compile BOOTLOADER main.c to main1.elf
"%RISCV_GCC_PATH%\%RISCV_PREFIX%gcc.exe" -march=rv32i -mabi=ilp32 -mno-relax -Os -nostartfiles -T bootloader.ld crt0.S ..\bootloader\main.c ..\common\common_lib.c -o main1.elf
"%RISCV_GCC_PATH%\%RISCV_PREFIX%objdump.exe" -d main1.elf > main1.dis

REM Show BOOTLOADER size summary
"%RISCV_GCC_PATH%\%RISCV_PREFIX%size.exe" main1.elf

REM Optional: Generate a hex file
"%RISCV_GCC_PATH%\%RISCV_PREFIX%objcopy.exe" -O ihex main1.elf main1.hex

echo Compilation finished.

REM ------------------------------------------------------------------
REM -- APP
REM ------------------------------------------------------------------
cd ..
cd %APP_DIR%
python gen_time_header.py
cd..
cd bootloader_and_app

REM Compile App main.c to main2.elf
"%RISCV_GCC_PATH%\%RISCV_PREFIX%gcc.exe" -march=rv32i -mabi=ilp32 -mno-relax -Os -nostartfiles -T app.ld crt0.S ..\%APP_DIR%\main.c ..\common\common_lib.c -o main2.elf
"%RISCV_GCC_PATH%\%RISCV_PREFIX%objdump.exe" -d main2.elf > main2.dis

REM Show App size summary
"%RISCV_GCC_PATH%\%RISCV_PREFIX%size.exe" main2.elf

REM Optional: Generate a hex file
"%RISCV_GCC_PATH%\%RISCV_PREFIX%objcopy.exe" -O ihex main2.elf main2.hex

python xilinx_hex_to_bytes.py
python xilinx_hex_to_ram_txt.py
 
echo FPGA ram generated.0