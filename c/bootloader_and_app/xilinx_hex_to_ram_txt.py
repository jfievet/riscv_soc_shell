def parse_intel_hex_line(line):
    if not line.startswith(":"):
        return None

    byte_count = int(line[1:3], 16)
    address = int(line[3:7], 16)
    record_type = int(line[7:9], 16)
    data = line[9:9 + byte_count * 2]
    bytes_list = [int(data[i:i + 2], 16) for i in range(0, len(data), 2)]
    if len(bytes_list) != byte_count:
        raise ValueError(f"Incomplete Intel HEX record: {line}")
    return byte_count, address, record_type, bytes_list


def load_hex_files(hex_files):
    """Collect data bytes by full address, without a fixed RAM window."""
    memory = {}

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
                        memory[full_address + i] = value
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

    if not memory:
        raise ValueError("No data bytes found in the input HEX files")
    base_address = min(memory)
    last_address = max(memory)
    if base_address % 4 != 0:
        raise ValueError(f"Image base 0x{base_address:08X} is not aligned to 4 bytes")
    return memory, base_address, last_address


def write_grouped_bytes(memory, output_file, base_address, last_address):
    """Write words as B3 B2 B1 B0, zero-filling internal gaps and padding."""
    with open(output_file, "w") as f:
        for address in range(base_address, last_address + 1, 4):
            group = [memory.get(address + i, 0) for i in range(4)]
            f.write(" ".join(f"{b:02X}" for b in reversed(group)) + "\n")


if __name__ == "__main__":
    HEX_FILES = ["main2.hex"]
    OUTPUT_FILE = "ram_data.txt"

    # Parse all inputs and validate the base before opening the output file.
    memory, base_address, last_address = load_hex_files(HEX_FILES)
    number_of_words = (last_address - base_address + 4) // 4
    write_grouped_bytes(memory, OUTPUT_FILE, base_address, last_address)

    print(f"Generated {OUTPUT_FILE} from: {', '.join(HEX_FILES)}")
    print(f"Image base: 0x{base_address:08X}")
    print(f"Last data address: 0x{last_address:08X}")
    print(f"Words generated: {number_of_words}")
    print("Set the UART loader APP_BASE to the image base shown above.")
