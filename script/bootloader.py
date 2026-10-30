import serial
import time
import msvcrt
import sys
from pathlib import Path


# ----------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------

COM_PORT = "COM7"
BAUDRATE = 250000

APP_BASE = 0x00001000
JUMP_ADDR = 0x00001000
#JUMP_ADDR = 0x00500000
#APP_BASE = 0x00500000

RAM_FILE = Path("../c/bootloader_and_app/ram_data.txt")

ACK_TIMEOUT_S = 2.0

SYNC_WRITE = 0xAA
SYNC_JUMP  = 0x55
SYNC_CONFIG_JUMP = 0xBB


# ----------------------------------------------------------------------
# UART helpers
# ----------------------------------------------------------------------

def read_exact(ser, number_of_bytes, timeout=2.0):
    """
    Read exactly number_of_bytes from UART.
    Return bytes on success, None on timeout.
    """

    data = bytearray()
    deadline = time.time() + timeout

    while len(data) < number_of_bytes:
        if time.time() > deadline:
            return None

        chunk = ser.read(number_of_bytes - len(data))

        if chunk:
            data.extend(chunk)

    return bytes(data)


def display_bootloader_output(ser, duration=1.0):
    """
    Display any text already being transmitted by the bootloader.
    """

    deadline = time.time() + duration

    while time.time() < deadline:
        waiting = ser.in_waiting

        if waiting:
            data = ser.read(waiting)

            try:
                sys.stdout.write(data.decode("utf-8", errors="replace"))
                sys.stdout.flush()
            except Exception:
                pass

            deadline = time.time() + 0.2

        else:
            time.sleep(0.01)


# ----------------------------------------------------------------------
# Bootloader protocol
# ----------------------------------------------------------------------

def generate_frame(sync, addr, data):
    """
    Generate the exact equivalent of the VHDL frame:

        BYTE 0 : sync
        BYTE 1 : ADDR[31:24]
        BYTE 2 : ADDR[23:16]
        BYTE 3 : ADDR[15:8]
        BYTE 4 : ADDR[7:0]
        BYTE 5 : DATA[31:24]
        BYTE 6 : DATA[23:16]
        BYTE 7 : DATA[15:8]
        BYTE 8 : DATA[7:0]

    Total = 9 bytes
    """

    return (
        bytes([sync]) +
        addr.to_bytes(4, byteorder="big") +
        data.to_bytes(4, byteorder="big")
    )


def configure_jump_address(ser, jump_addr):
    """Configure the execution address independently of the upload address."""
    frame = generate_frame(SYNC_CONFIG_JUMP, 0, jump_addr)

    ser.write(frame)
    ser.flush()

    ack = read_exact(ser, 9, ACK_TIMEOUT_S)

    if ack is None:
        print("\nERROR: Jump address configuration ACK timeout.")
        return False

    if ack != frame:
        print("\nERROR: Incorrect jump address configuration ACK.")
        print(f"Expected : {frame.hex(' ')}")
        print(f"Received : {ack.hex(' ')}")
        return False

    print(f"Jump address configured: 0x{jump_addr:08X}")
    return True


def write_word(ser, addr, data):
    """
    Send one 32-bit word and verify the bootloader ACK.
    """

    frame = generate_frame(SYNC_WRITE, addr, data)

    ser.write(frame)
    ser.flush()

    ack = read_exact(ser, 9, ACK_TIMEOUT_S)

    if ack is None:
        print(f"\nERROR: ACK timeout at address 0x{addr:08X}")
        return False

    # The bootloader sends:
    #
    #   0xAA + address + data
    #
    expected_ack = generate_frame(SYNC_WRITE, addr, data)

    if ack != expected_ack:
        print(f"\nERROR: Incorrect ACK at address 0x{addr:08X}")
        print(f"Expected : {expected_ack.hex(' ')}")
        print(f"Received : {ack.hex(' ')}")
        return False

    return True


# ----------------------------------------------------------------------
# RAM file
# ----------------------------------------------------------------------

def read_ram_file(filename):
    """
    Read ram_data.txt.

    Expected format, for example:

        13 05 00 00
        93 85 05 00
        ...

    Equivalent to the four hread() operations used in the VHDL testcase.
    """

    words = []

    with open(filename, "r") as f:

        for line_number, line in enumerate(f, start=1):

            # Remove comments
            line = line.split("#")[0].strip()

            if not line:
                continue

            parts = line.split()

            if len(parts) == 4:
                try:
                    b3 = int(parts[0], 16)
                    b2 = int(parts[1], 16)
                    b1 = int(parts[2], 16)
                    b0 = int(parts[3], 16)

                except ValueError:
                    raise ValueError(
                        f"Invalid hexadecimal data line {line_number}: {line}"
                    )

                word = (
                    (b3 << 24) |
                    (b2 << 16) |
                    (b1 << 8) |
                    b0
                )

            elif len(parts) == 1 and len(parts[0]) == 8:

                # Also accept:
                #
                # 13050000
                #
                word = int(parts[0], 16)

            else:
                raise ValueError(
                    f"Invalid RAM file format line {line_number}: {line}"
                )

            words.append(word)

    return words


# ----------------------------------------------------------------------
# Upload application
# ----------------------------------------------------------------------

def upload_application(ser, filename):

    words = read_ram_file(filename)

    if not words:
        print("ERROR: RAM file is empty")
        return None

    print()
    print("-----------------------------------------------")
    print("Start to send app")
    print("-----------------------------------------------")
    print(f"File       : {filename}")
    print(f"Start addr : 0x{APP_BASE:08X}")
    print(f"Words      : {len(words)}")
    print(f"Size       : {len(words) * 4} bytes")
    print()

    addr = APP_BASE

    for index, data in enumerate(words):

        if not write_word(ser, addr, data):
            return None

        # Progress
        percent = ((index + 1) * 100) // len(words)

        print(
            f"\rUploading: {percent:3d}% "
            f"({index + 1}/{len(words)}) "
            f"addr=0x{addr:08X}",
            end="",
            flush=True
        )

        addr += 4

    print()
    print()
    print("Application upload completed successfully.")

    # Return the last address/data.
    #
    # This is useful for the jump frame because the current bootloader
    # writes ADDR/DATA even for the 0x55 command.
    last_addr = APP_BASE + (len(words) - 1) * 4
    last_data = words[-1]

    return last_addr, last_data


# ----------------------------------------------------------------------
# Jump command
# ----------------------------------------------------------------------

def send_jump_request(ser, addr, data):

    print()
    print("-----------------------------------------------")
    print("Request application jump")
    print("-----------------------------------------------")

    #
    # IMPORTANT:
    #
    # Your bootloader writes addr/data even when SYNC = 0x55.
    #
    # Rather than writing an additional word after the application
    # like the VHDL testcase currently does, rewrite the LAST word
    # with exactly the same value.
    #
    # This avoids modifying RAM beyond the application image.
    #

    frame = generate_frame(SYNC_JUMP, addr, data)

    ser.write(frame)
    ser.flush()

    #
    # The ACK is still 0xAA, not 0x55.
    #

    expected_ack = generate_frame(SYNC_WRITE, addr, data)

    ack = read_exact(ser, 9, ACK_TIMEOUT_S)

    if ack is None:
        print("ERROR: Jump command ACK timeout.")
        return False

    if ack != expected_ack:
        print("ERROR: Incorrect jump command ACK.")
        print(f"Expected : {expected_ack.hex(' ')}")
        print(f"Received : {ack.hex(' ')}")
        return False

    print("Jump frame acknowledged.")
    print()

    return True


# ----------------------------------------------------------------------
# Wait for "Press y to jump"
# ----------------------------------------------------------------------

def wait_for_jump_prompt(ser, timeout=5.0):

    expected = b"Press y to jump"

    received = bytearray()

    deadline = time.time() + timeout

    while time.time() < deadline:

        ch = ser.read(1)

        if ch:
            received.extend(ch)

            # Display exactly what comes from RISC-V
            sys.stdout.buffer.write(ch)
            sys.stdout.buffer.flush()

            if expected in received:
                return True

    return False


# ----------------------------------------------------------------------
# UART terminal
# ----------------------------------------------------------------------

def uart_terminal(ser):
    """
    Simple PuTTY-like UART console.

    Everything received from the FPGA is displayed.
    Everything typed on the keyboard is sent to the FPGA.

    Ctrl+] exits the terminal.
    """

    print()
    print("-----------------------------------------------")
    print("UART terminal")
    print("-----------------------------------------------")
    print("Ctrl+] to exit")
    print()

    while True:

        # --------------------------------------------------------------
        # FPGA -> PC
        # --------------------------------------------------------------

        waiting = ser.in_waiting

        if waiting:
            data = ser.read(waiting)

            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()

        # --------------------------------------------------------------
        # PC -> FPGA
        # --------------------------------------------------------------

        if msvcrt.kbhit():

            ch = msvcrt.getwch()

            # Ctrl+]
            if ch == "\x1d":
                print()
                print("Leaving UART terminal.")
                break

            # Extended Windows key
            if ch in ("\x00", "\xe0"):
                msvcrt.getwch()
                continue

            # ENTER
            if ch == "\r":
                ser.write(b"\r")
                ser.flush()
                continue

            try:
                ser.write(ch.encode("latin-1"))
                ser.flush()
            except UnicodeEncodeError:
                pass

        time.sleep(0.001)


# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------

def main():

    print("-----------------------------------------------")
    print("RISC-V UART application loader")
    print("-----------------------------------------------")
    print()

    try:

        ser = serial.Serial(
            COM_PORT,
            baudrate=BAUDRATE,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.05
        )

    except serial.SerialException as e:
        print(f"ERROR: Cannot open {COM_PORT}")
        print(e)
        return

    print(f"UART opened: {COM_PORT} @ {BAUDRATE} baud")
    print()

    try:

        # --------------------------------------------------------------
        # Display bootloader startup messages
        # --------------------------------------------------------------

        print("Bootloader output:")
        print()

        display_bootloader_output(ser, duration=1.0)

        print()

        # --------------------------------------------------------------
        # Upload application
        # --------------------------------------------------------------

        if not configure_jump_address(ser, JUMP_ADDR):
            return

        result = upload_application(ser, RAM_FILE)

        if result is None:
            return

        last_addr, last_data = result

        # --------------------------------------------------------------
        # Tell bootloader that upload is finished
        # --------------------------------------------------------------

        if not send_jump_request(
            ser,
            last_addr,
            last_data
        ):
            return

        # --------------------------------------------------------------
        # Wait for bootloader:
        #
        #     Press y to jump
        #
        # --------------------------------------------------------------

        if not wait_for_jump_prompt(ser):

            print()
            print("ERROR: Bootloader 'Press y to jump' prompt not received.")
            return

        print()
        print()
        print("-----------------------------------------------")
        print("Application is ready to start.")
        print("-----------------------------------------------")
        print()
        print("Press 'y' to jump to the RISC-V application.")

        # --------------------------------------------------------------
        # USER confirmation
        # --------------------------------------------------------------

        while True:

            ch = msvcrt.getwch()

            if ch.lower() == "y":
                break

        print("y")

        # Send ASCII y = 0x79
        ser.write(b"y")
        ser.flush()

        print()
        print("Jump command sent.")
        print()

        # Small delay only to separate the two operating modes.
        time.sleep(0.05)

        # --------------------------------------------------------------
        # From this point the PC becomes a UART terminal
        # --------------------------------------------------------------

        uart_terminal(ser)

    except KeyboardInterrupt:

        print()
        print("Interrupted.")

    finally:

        ser.close()
        print("UART closed.")


# ----------------------------------------------------------------------
# Entry point
# ----------------------------------------------------------------------

if __name__ == "__main__":
    main()
