import os
import math
import subprocess

def parse_intel_hex_line(line):
    if not line.startswith(":"):
        return None

    byte_count = int(line[1:3], 16)
    address = int(line[3:7], 16)
    record_type = int(line[7:9], 16)
    data = line[9:9 + byte_count * 2]

    bytes_list = [int(data[i:i + 2], 16) for i in range(0, len(data), 2)]
    return byte_count, address, record_type, bytes_list


def load_hex_files(hex_files, mem_size_bytes):
    memory = [0] * mem_size_bytes
    upper_address = 0

    for filename in hex_files:
        upper_address = 0
        with open(filename, "r") as f:
            for raw_line in f:
                line = raw_line.strip()
                if not line:
                    continue

                parsed = parse_intel_hex_line(line)
                if parsed is None:
                    continue

                byte_count, address, record_type, bytes_list = parsed

                if record_type == 0x00:
                    full_address = upper_address + address
                    for i, value in enumerate(bytes_list):
                        idx = full_address + i
                        if 0 <= idx < mem_size_bytes:
                            memory[idx] = value

                elif record_type == 0x01:
                    break

                elif record_type == 0x04:
                    if byte_count != 2:
                        raise ValueError(f"Invalid extended linear address record in {filename}: {line}")
                    upper_address = ((bytes_list[0] << 8) | bytes_list[1]) << 16

                elif record_type == 0x02:
                    if byte_count != 2:
                        raise ValueError(f"Invalid extended segment address record in {filename}: {line}")
                    upper_address = ((bytes_list[0] << 8) | bytes_list[1]) << 4

    return memory


def write_grouped_bytes(byte_list, output_file, start_word=0):
    start_byte = start_word * 4
    with open(output_file, "w") as f:
        for i in range(start_byte, len(byte_list), 4):
            group = byte_list[i:i + 4]
            while len(group) < 4:
                group.append(0)
            f.write(" ".join(f"{b:02X}" for b in reversed(group)) + "\n")


def get_elf_size(elf_file):
    gcc_path = os.environ.get("RISCV_GCC_PATH")
    riscv_prefix = os.environ.get("RISCV_PREFIX")

    if gcc_path is None:
        raise RuntimeError("RISCV_GCC_PATH environment variable is not defined")

    if riscv_prefix is None:
        raise RuntimeError("RISCV_PREFIX environment variable is not defined")

    size_exe = os.path.join(
        gcc_path,
        f"{riscv_prefix}size.exe"
    )

    result = subprocess.run(
        [size_exe, elf_file],
        capture_output=True,
        text=True,
        check=True
    )

    print("\nApplication size:")
    print(result.stdout.strip())

    lines = result.stdout.strip().splitlines()

    # Expected format:
    #
    #    text    data     bss     dec     hex filename
    #    1602      24       0    1626     65a main2.elf
    #
    if len(lines) < 2:
        raise RuntimeError(
            f"Unexpected output from size.exe:\n{result.stdout}"
        )

    fields = lines[-1].split()

    if len(fields) < 6:
        raise RuntimeError(
            f"Unable to parse size.exe output:\n{result.stdout}"
        )

    dec_size = int(fields[3])

    return dec_size


def truncate_ram_data(output_file, size_bytes):
    number_of_words = math.ceil(size_bytes / 4)

    with open(output_file, "r") as f:
        lines = f.readlines()

    if number_of_words > len(lines):
        raise RuntimeError(
            f"Application requires {number_of_words} RAM words, "
            f"but {output_file} contains only {len(lines)} words"
        )

    with open(output_file, "w") as f:
        f.writelines(lines[:number_of_words])

    print(
        f"Trimmed {output_file} to {number_of_words} words "
        f"({size_bytes} application bytes)"
    )

if __name__ == "__main__":
    HEX_FILES = [ "main2.hex"]
    OUTPUT_FILE = "ram_data.txt"
    ELF_FILE = "main2.elf"


    MEM_SIZE_BYTES = 65536

    memory = load_hex_files(HEX_FILES, MEM_SIZE_BYTES)
    write_grouped_bytes(memory, OUTPUT_FILE, start_word=1024)

    print(f"Generated {OUTPUT_FILE} from: {', '.join(HEX_FILES)}")

    # ------------------------------------------------------------
    # Get application size from ELF
    # ------------------------------------------------------------
    app_size_bytes = get_elf_size(ELF_FILE)

    # ------------------------------------------------------------
    # Keep only the RAM words actually required by the application
    # ------------------------------------------------------------
    truncate_ram_data(
        OUTPUT_FILE,
        app_size_bytes
    )