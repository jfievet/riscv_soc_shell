#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include "generated_header.h"
#include "../common/common_lib.h"

// ============================================================
// Configuration
// ============================================================

#define SDRAM_BASE_ADDR    0x00500000U
#define SDRAM_TEST_WORDS   101U

#define SDRAM_SIZE_BYTES      0x00800000U
#define SDRAM_TOTAL_WORDS     (SDRAM_SIZE_BYTES / 4U)
#define SDRAM_MAX_ERRORS      20U
#define SDRAM_PROGRESS_WORDS 200000U

#if SDRAM_PROGRESS_WORDS == 0
#error "SDRAM_PROGRESS_WORDS must be greater than zero"
#endif

// ============================================================
// Register addresses
// ============================================================

#define TIME_FREQ_ADDR     0x0030000C
#define TIME_LOW_ADDR      0x00300010
#define TIME_HIGH_ADDR     0x00300014

// ============================================================
// Register access
// ============================================================

static uint32_t read_reg(uint32_t addr)
{
    return *(volatile uint32_t *)(uintptr_t)addr;
}

static void write_reg(uint32_t addr, uint32_t value)
{
    *(volatile uint32_t *)(uintptr_t)addr = value;
}

// ============================================================
// UART helpers
// ============================================================

static void wait_uart_tx(void)
{
    volatile uint32_t *level_reg =
        (volatile uint32_t *)(UART_TX_ADDR + 8);

    while (*level_reg != 0) {
        // Wait until TX FIFO is empty
    }
}

static void print_hex64(uint64_t value)
{
    dprint("0x");
    uart_send_hex((uint32_t)(value >> 32));
    uart_send_hex((uint32_t)value);
}

static uint8_t read_menu_key(void)
{
    uint8_t c;

    do {
        c = dget();
    } while (c == '\r' || c == '\n');

    return c;
}

// ============================================================
// Time elapsed
// ============================================================

static uint64_t read_elapsed_time(void)
{
    // Reading frequency triggers counter capture
    uint32_t freq = read_reg(TIME_FREQ_ADDR);
    (void)freq;

    uint32_t low  = read_reg(TIME_LOW_ADDR);
    uint32_t high = read_reg(TIME_HIGH_ADDR);

    return ((uint64_t)high << 32) | low;
}

// ============================================================
// Convert elapsed clock cycles to microseconds
// ============================================================

static uint64_t cycles_to_us(uint64_t cycles, uint32_t freq_hz)
{
    if (freq_hz == 0U) {
        return 0U;
    }

    uint64_t seconds = cycles / freq_hz;
    uint64_t remainder = cycles % freq_hz;

    return seconds * 1000000ULL
         + (remainder * 1000000ULL) / freq_hz;
}

// ============================================================
// Option 1 - FPGA / Firmware information
// ============================================================

static void show_system_information(void)
{
    uint32_t reg0 = read_reg(AXI_SLAVE_REG_REG0);
    uint32_t reg1 = read_reg(AXI_SLAVE_REG_REG1);

    int day   = (int)(reg0 & 0xFF);
    int month = (int)((reg0 >> 8) & 0xFF);
    int year  = (int)((reg0 >> 16) & 0xFFFF);

    int hour   = (int)(reg1 & 0xFF);
    int minute = (int)((reg1 >> 8) & 0xFF);
    int second = (int)((reg1 >> 16) & 0xFF);

    uint32_t sys_freq = read_reg(TIME_FREQ_ADDR);
    uint64_t elapsed = read_elapsed_time();

    dprint("\r\n========== SYSTEM INFORMATION ==========\r\n");

    dprint("FPGA build date: %d/%d/%d\r\n",
           day, month, year);

    dprint("FPGA build time: %d:%d:%d\r\n",
           hour, minute, second);

    dprint("ELF build date: %d/%d/%d\r\n",
           generated_day,
           generated_month,
           generated_year);

    dprint("ELF build time: %d:%d:%d\r\n",
           generated_hour,
           generated_minute,
           generated_second);

    dprint("FPGA system frequency: %d Hz\r\n",
           (int)sys_freq);

    dprint("Time elapsed: ");
    print_hex64(elapsed);
    dprint("\r\n");

    wait_uart_tx();
}

// ============================================================
// Options 2 and 3 - SDRAM write/read test
// ============================================================

static void test_sdram_scan(bool verbose)
{
    uint32_t errors = 0;
    uint32_t addr;
    uint32_t expected;
    uint32_t actual;

    uint32_t sys_freq;
    uint64_t start_time;
    uint64_t end_time;
    uint64_t delta_cycles;
    uint64_t duration_us;

    // Store read values for verbose display after timing
    static uint32_t read_values[SDRAM_TEST_WORDS];

    // --------------------------------------------------------
    // Test information
    // --------------------------------------------------------

    dprint("\r\n========== SDRAM WRITE/READ TEST ==========\r\n");

    dprint("Base address: 0x");
    uart_send_hex(SDRAM_BASE_ADDR);
    dprint("\r\n");

    dprint("Number of words: %d\r\n", (int)SDRAM_TEST_WORDS);

    if (verbose) {
        dprint("Verbose mode: ENABLED\r\n");
    } else {
        dprint("Verbose mode: DISABLED\r\n");
    }

    sys_freq = read_reg(TIME_FREQ_ADDR);

    // --------------------------------------------------------
    // Start timing
    // --------------------------------------------------------

    start_time = read_elapsed_time();

    // --------------------------------------------------------
    // Write phase
    // --------------------------------------------------------

    for (uint32_t i = 0; i < SDRAM_TEST_WORDS; i++) {

        addr = SDRAM_BASE_ADDR + (i * 4U);
        expected = 0xA5A50000U | i;

        write_reg(addr, expected);
    }

    // --------------------------------------------------------
    // Read and verify phase
    // --------------------------------------------------------

    for (uint32_t i = 0; i < SDRAM_TEST_WORDS; i++) {

        addr = SDRAM_BASE_ADDR + (i * 4U);
        expected = 0xA5A50000U | i;

        actual = read_reg(addr);

        if (verbose) {
            read_values[i] = actual;
        }

        if (actual != expected) {
            errors++;
        }
    }

    // --------------------------------------------------------
    // End timing
    // --------------------------------------------------------

    end_time = read_elapsed_time();

    delta_cycles = end_time - start_time;
    duration_us = cycles_to_us(delta_cycles, sys_freq);

    // --------------------------------------------------------
    // Verbose display (option 3)
    // --------------------------------------------------------

    if (verbose) {

        dprint("\r\n========== SDRAM DATA DETAILS ==========\r\n");

        for (uint32_t i = 0; i < SDRAM_TEST_WORDS; i++) {

            addr = SDRAM_BASE_ADDR + (i * 4U);
            expected = 0xA5A50000U | i;
            actual = read_values[i];

            dprint("ADDR: 0x");
            uart_send_hex(addr);

            dprint(" WRITE: 0x");
            uart_send_hex(expected);

            dprint(" READ: 0x");
            uart_send_hex(actual);

            if (actual == expected) {
                dprint(" OK");
            } else {
                dprint(" ERROR");
            }

            dprint("\r\n");
        }
    }

    // --------------------------------------------------------
    // Timing results
    // --------------------------------------------------------

    dprint("\r\n========== TIMING RESULTS ==========\r\n");

    dprint("Start time:     ");
    print_hex64(start_time);
    dprint("\r\n");

    dprint("End time:       ");
    print_hex64(end_time);
    dprint("\r\n");

    dprint("Elapsed cycles: ");
    print_hex64(delta_cycles);
    dprint("\r\n");

    dprint("Duration (us):  %d\r\n", (int)duration_us);

    dprint("System freq:    %d Hz\r\n", (int)sys_freq);

    // --------------------------------------------------------
    // SDRAM test results
    // --------------------------------------------------------

    dprint("\r\n========== SDRAM TEST RESULTS ==========\r\n");

    dprint("Words tested: %d\r\n", (int)SDRAM_TEST_WORDS);
    dprint("Total errors: %d\r\n", (int)errors);

    if (errors == 0) {
        dprint("SDRAM TEST PASSED\r\n");
        gpio_write(0x04);
    } else {
        dprint("SDRAM TEST FAILED\r\n");
        gpio_write(0x08);
    }

    dprint("========================================\r\n");

    wait_uart_tx();
}

// ============================================================
// Option 4 - SDRAM single address test
// ============================================================

static void test_sdram_single(void)
{
    uint32_t addr = SDRAM_BASE_ADDR;
    uint32_t errors = 0;
    uint32_t actual;

    const uint32_t patterns[] = {
        0x00000000U,
        0xFFFFFFFFU,
        0x12345678U,
        0xAAAAAAAAU,
        0x55555555U,
        0x00000000U,
        0xFFFFFFFFU,
        0x12345678U,
        0x56781234U,
        0x0000FFFFU,
        0xFFFF0000U,
        0xAAAA5555U,
        0x5555AAAAU,
        0x00000001U,
        0x00010000U
    };

    dprint("\r\n========== SDRAM SINGLE ADDRESS TEST ==========\r\n");

    dprint("Address: 0x");
    uart_send_hex(addr);
    dprint("\r\n\r\n");

    for (uint32_t i = 0; i < 15; i++) {

        // Write pattern
        write_reg(addr, patterns[i]);

        // Immediately read back
        actual = read_reg(addr);

        dprint("WRITE: 0x");
        uart_send_hex(patterns[i]);

        dprint(" READ: 0x");
        uart_send_hex(actual);

        if (actual == patterns[i]) {
            dprint(" OK");
        } else {
            dprint(" ERROR");
            errors++;
        }

        dprint("\r\n");
    }

    dprint("\r\n========== TEST RESULTS ==========\r\n");
    dprint("Patterns tested: 15\r\n");
    dprint("Total errors: %d\r\n", (int)errors);

    if (errors == 0) {
        dprint("SDRAM SINGLE ADDRESS TEST PASSED\r\n");
        gpio_write(0x04);
    } else {
        dprint("SDRAM SINGLE ADDRESS TEST FAILED\r\n");
        gpio_write(0x08);
    }

    dprint("==================================\r\n");

    wait_uart_tx();
}

// ============================================================
// Option 5 - Full SDRAM test (8 MiB)
// ============================================================

static uint32_t sdram_pattern(uint32_t index)
{
    uint32_t x = index ^ 0xA5A55A5AU;

    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;

    return x;
}

static void test_sdram_full(void)
{
    uint32_t errors = 0;
    uint32_t addr;
    uint32_t expected;
    uint32_t actual;

    uint32_t sys_freq;

    uint64_t start_time;
    uint64_t write_end_time;
    uint64_t end_time;

    uint64_t write_cycles;
    uint64_t read_cycles;
    uint64_t total_cycles;

    dprint("\r\n========== FULL SDRAM TEST ==========\r\n");

    dprint("Base address: 0x");
    uart_send_hex(SDRAM_BASE_ADDR);
    dprint("\r\n");

    dprint("Size: 8 MiB\r\n");
    dprint("Words: %d\r\n", (int)SDRAM_TOTAL_WORDS);

    dprint("\r\nWARNING: SDRAM CONTENT WILL BE OVERWRITTEN\r\n");

    sys_freq = read_reg(TIME_FREQ_ADDR);

    // --------------------------------------------------------
    // Write phase
    // --------------------------------------------------------

    dprint("\r\nWriting SDRAM...\r\n");

    start_time = read_elapsed_time();

    for (uint32_t i = 0; i < SDRAM_TOTAL_WORDS; i++) {

        addr = SDRAM_BASE_ADDR + (i * 4U);
        expected = sdram_pattern(i);

        write_reg(addr, expected);

        uint32_t completed_words = i + 1U;
        if ((completed_words % SDRAM_PROGRESS_WORDS) == 0U ||
            completed_words == SDRAM_TOTAL_WORDS) {
            dprint("Write progress: %d / %d words\r\n",
                   (int)completed_words, (int)SDRAM_TOTAL_WORDS);
        }
    }

    write_end_time = read_elapsed_time();

    dprint("\r\nWrite completed.\r\n");

    // --------------------------------------------------------
    // Read and verify phase
    // --------------------------------------------------------

    dprint("\r\nReading and verifying SDRAM...\r\n");

    for (uint32_t i = 0; i < SDRAM_TOTAL_WORDS; i++) {

        addr = SDRAM_BASE_ADDR + (i * 4U);
        expected = sdram_pattern(i);

        actual = read_reg(addr);

        if (actual != expected) {

            errors++;

            if (errors <= SDRAM_MAX_ERRORS) {

                dprint("\r\nERROR at 0x");
                uart_send_hex(addr);

                dprint(" EXPECTED: 0x");
                uart_send_hex(expected);

                dprint(" ACTUAL: 0x");
                uart_send_hex(actual);

                dprint("\r\n");
            }
        }

        uint32_t completed_words = i + 1U;
        if ((completed_words % SDRAM_PROGRESS_WORDS) == 0U ||
            completed_words == SDRAM_TOTAL_WORDS) {
            dprint("Read progress: %d / %d words\r\n",
                   (int)completed_words, (int)SDRAM_TOTAL_WORDS);
        }
    }

    end_time = read_elapsed_time();

    dprint("\r\nRead completed.\r\n");

    // --------------------------------------------------------
    // Timing results
    // --------------------------------------------------------

    write_cycles = write_end_time - start_time;
    read_cycles = end_time - write_end_time;
    total_cycles = end_time - start_time;

    dprint("\r\n========== TIMING RESULTS ==========\r\n");

    dprint("Write cycles: ");
    print_hex64(write_cycles);
    dprint("\r\n");

    dprint("Read cycles:  ");
    print_hex64(read_cycles);
    dprint("\r\n");

    dprint("Total cycles: ");
    print_hex64(total_cycles);
    dprint("\r\n");

    dprint("Write time (us): %d\r\n",
           (int)cycles_to_us(write_cycles, sys_freq));

    dprint("Read time (us):  %d\r\n",
           (int)cycles_to_us(read_cycles, sys_freq));

    dprint("Total time (us): %d\r\n",
           (int)cycles_to_us(total_cycles, sys_freq));

    // --------------------------------------------------------
    // Test results
    // --------------------------------------------------------

    dprint("\r\n========== SDRAM TEST RESULTS ==========\r\n");

    dprint("Words tested: %d\r\n", (int)SDRAM_TOTAL_WORDS);
    dprint("Total errors: %d\r\n", (int)errors);

    if (errors == 0U) {
        dprint("FULL SDRAM TEST PASSED\r\n");
        gpio_write(0x04);
    } else {
        dprint("FULL SDRAM TEST FAILED\r\n");
        gpio_write(0x08);
    }

    dprint("========================================\r\n");

    wait_uart_tx();
}

// ============================================================
// Main menu
// ============================================================

static void show_menu(void)
{
    dprint("\r\n");
    dprint("========== FPGA TEST MENU ==========\r\n");
    dprint("1. FPGA / Firmware Information\r\n");
    dprint("2. SDRAM Write/Read Test (0-100)\r\n");
    dprint("3. SDRAM Write/Read Test + Data Display\r\n");
    dprint("4. SDRAM Single Address Test\r\n");
    dprint("5. Full SDRAM Test (8 MiB)\r\n");
    dprint("====================================\r\n");
    dprint("Select an option (1-5): ");

    wait_uart_tx();
}

// ============================================================
// Main
// ============================================================

int main(void)
{
    uint8_t choice;

    gpio_write(0x01);

    while (1) {

        show_menu();

        choice = read_menu_key();

        switch (choice) {

            case '1':
                gpio_write(0x01);
                show_system_information();
                break;

            case '2':
                gpio_write(0x02);
                test_sdram_scan(false);
                break;

            case '3':
                gpio_write(0x03);
                test_sdram_scan(true);
                break;
                
            case '4':
                gpio_write(0x04);
                test_sdram_single();
                break;
                
            case '5':
                gpio_write(0x02);
                test_sdram_full();
                break;

            default:
                dprint("\r\nInvalid option. Please select 1, 2, 3, 4, or 5.\r\n");
                break;
        }
    }

    return 0;
}
