
#!/usr/bin/env bash
set -e

# Compile main.c for PicoRV32 (RISC-V)

# Move to the script directory
cd "$(dirname "$0")"

# Generate time header
python3 gen_time_header.py

# RISC-V GCC toolchain
RISCV_GCC_PATH="/opt/riscv/bin"
RISCV_PREFIX="riscv-none-elf-"

# Use toolchain from PATH if available
if command -v "${RISCV_PREFIX}gcc" >/dev/null 2>&1; then
    RISCV_GCC="${RISCV_PREFIX}"
else
    RISCV_GCC="${RISCV_GCC_PATH}/${RISCV_PREFIX}"
fi

# Compile main.c to main.elf
"${RISCV_GCC}gcc" \
    -march=rv32i \
    -mabi=ilp32 \
    -mno-relax \
    -Os \
    -nostartfiles \
    -T link.ld \
    crt0.S main.c ../common/common_lib.c \
    -o main.elf

# Generate disassembly
"${RISCV_GCC}objdump" -d main.elf > main.dis

# Show size summary
"${RISCV_GCC}size" main.elf

# Generate Intel HEX file
"${RISCV_GCC}objcopy" -O ihex main.elf main.hex

echo "Compilation finished."

# Generate FPGA RAM
python3 xilinx_hex_to_bytes.py

echo "FPGA RAM generated."
