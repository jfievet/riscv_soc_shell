from pathlib import Path

def parse_intel_hex_line(line):
    if not line.startswith(':'):
        return None
    byte_count = int(line[1:3], 16)
    address = int(line[3:7], 16)
    record_type = int(line[7:9], 16)
    data = line[9:9 + byte_count * 2]
    if record_type != 0x00:
        return None
    bytes_list = [int(data[i:i+2], 16) for i in range(0, len(data), 2)]
    return address, bytes_list

def read_hex_file(filename, mem_size=256):
    memory = [0] * mem_size
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            result = parse_intel_hex_line(line)
            if result:
                address, bytes_list = result
                for i, b in enumerate(bytes_list):
                    idx = address + i
                    if 0 <= idx < mem_size:
                        memory[idx] = b
    return memory

def write_grouped_bytes(byte_list, output_file):
    with open(output_file, "w") as f:
        for i in range(0, len(byte_list), 4):
            group = byte_list[i:i+4]
            # Pad with zeros if less than 4 bytes at the end
            while len(group) < 4:
                group.append(0)
            # Write in reverse order: B3 B2 B1 B0
            f.write(" ".join(f"{b:02X}" for b in reversed(group)) + "\n")

if __name__ == "__main__":
    SCRIPT_DIR = Path(__file__).resolve().parent

    HEX_FILENAME = SCRIPT_DIR / "main.hex"
    OUTPUT_FILE = SCRIPT_DIR / "ram_data.txt"

    VHDL_OUTPUT = "../../src/rams_sp_wf_pkg.vhd"
    VHDL_DEPTH = 16384

    byte_list = read_hex_file(HEX_FILENAME, mem_size=VHDL_DEPTH)
    write_grouped_bytes(byte_list, OUTPUT_FILE)
    
    # Write VHDL RAM initialization ? one constant per byte lane
##    with open(VHDL_OUTPUT, "w") as vhdl:
##        vhdl.write("library ieee;\n")
##        vhdl.write("use ieee.std_logic_1164.all;\n")
##        vhdl.write("use ieee.numeric_std.all;\n\n")
##        vhdl.write("package rams_sp_wf_pkg is\n\n")
##        vhdl.write(f"    constant G_DEPTH : integer := {VHDL_DEPTH};\n\n")
##        vhdl.write("    type ram_type is array (G_DEPTH-1 downto 0) of std_logic_vector(7 downto 0);\n\n")
##
##        for lane in range(4):
##            const_name = f"C_RAM_{lane}_INIT"
##            vhdl.write(f"    constant {const_name} : ram_type := (\n")
##            for i in range(VHDL_DEPTH):
##                byte_idx = i * 4 + lane
##                b = byte_list[byte_idx] if byte_idx < len(byte_list) else 0
##                vhdl.write(f'        {i} => x"{b:02X}"')
##                if i < VHDL_DEPTH - 1:
##                    vhdl.write(",\n")
##                else:
##                    vhdl.write("\n")
##            vhdl.write("    );\n\n")
##
##        vhdl.write("end package rams_sp_wf_pkg;\n")
