@echo off
REM Batch script to compile bootload and app for PicoRV32 (RISC-V)

REM ------------------------------------------------------------------
REM -- Configuration
REM ------------------------------------------------------------------

set APP_DIR=axi_write_loopback
set "APP_MEMORY=BRAM"

REM Select the application linker script before generating or compiling files.
set "APP_LINKER_SCRIPT="
if /I "%APP_MEMORY%"=="BRAM" set "APP_LINKER_SCRIPT=app_bram.ld"
if /I "%APP_MEMORY%"=="SDRAM" set "APP_LINKER_SCRIPT=app_sdram.ld"

if not defined APP_LINKER_SCRIPT (
    echo ERROR: Invalid APP_MEMORY "%APP_MEMORY%". Use BRAM or SDRAM.
    exit /b 1
)

if not exist "%~dp0%APP_LINKER_SCRIPT%" (
    echo ERROR: Linker script "%~dp0%APP_LINKER_SCRIPT%" not found.
    exit /b 1
)

echo Application: %APP_DIR%
echo Application memory: %APP_MEMORY%
echo Application linker script: %APP_LINKER_SCRIPT%

if /I "%APP_MEMORY%"=="SDRAM" (
    echo WARNING: SDRAM selection changes application link placement only.
    echo WARNING: The bootloader still jumps to 0x00001000; image converters are unchanged.
    if /I "%APP_DIR%"=="sdram_scan" (
        echo WARNING: Destructive SDRAM tests can overwrite the application and its stack.
    )
)

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
"%RISCV_GCC_PATH%\%RISCV_PREFIX%gcc.exe" -march=rv32i -mabi=ilp32 -mno-relax -Os -nostartfiles -T "%APP_LINKER_SCRIPT%" crt0.S ..\%APP_DIR%\main.c ..\common\common_lib.c -o main2.elf
if errorlevel 1 (
    echo ERROR: Application compilation failed.
    exit /b 1
)
"%RISCV_GCC_PATH%\%RISCV_PREFIX%objdump.exe" -d main2.elf > main2.dis

REM Show App size summary
"%RISCV_GCC_PATH%\%RISCV_PREFIX%size.exe" main2.elf

REM Optional: Generate a hex file
"%RISCV_GCC_PATH%\%RISCV_PREFIX%objcopy.exe" -O ihex main2.elf main2.hex

python xilinx_hex_to_bytes.py
python xilinx_hex_to_ram_txt.py
 
echo FPGA ram generated.0
