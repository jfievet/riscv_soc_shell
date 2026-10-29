#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdbool.h>

#include "generated_header.h"
#include "../common/common_lib.h"

// ============================================================
// Configuration
// ============================================================

#define TRNG_ACCUM_CYCLES     20U
#define TRNG_TEST_ITERATIONS  100000U
#define TRNG_TIMEOUT          1000000U

// ============================================================
// Register addresses
// ============================================================

// Time elapsed
#define TIME_FREQ_ADDR       0x0030000C
#define TIME_LOW_ADDR        0x00300010
#define TIME_HIGH_ADDR       0x00300014

// TRNG
#define TRNG_CONTROL_ADDR    0x00400000
#define TRNG_STATUS_ADDR     0x00400004
#define TRNG_DATA_ADDR       0x00400008
#define TRNG_ACCUM_ADDR      0x0040000C

// TRNG commands
#define TRNG_START           1U
#define TRNG_CLEAR           2U

// TRNG status
#define TRNG_IDLE            0U
#define TRNG_BUSY            1U
#define TRNG_DONE            2U


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

static bool wait_for_next_measurement(void)
{
    uint8_t c;

    dprint("\r\nPress Enter to run again, or q to return to menu...\r\n");
    wait_uart_tx();

    while (1) {

        c = dget();

        if (c == '\r' || c == '\n') {
            return true;
        }

        if (c == 'q' || c == 'Q') {
            return false;
        }
    }
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
// TRNG measurement structure
// ============================================================

typedef struct {
    uint64_t start_time;
    uint64_t end_time;
    uint64_t delta_cycles;
    uint32_t random_data;
} trng_measurement_t;


// ============================================================
// Perform one TRNG acquisition
// ============================================================

static bool trng_acquire(uint32_t *random_data)
{
    uint32_t status;
    uint32_t timeout;

    // Clear previous acquisition
    write_reg(TRNG_CONTROL_ADDR, TRNG_CLEAR);

    // Configure accumulation cycles
    write_reg(TRNG_ACCUM_ADDR, TRNG_ACCUM_CYCLES);

    // Verify configuration
    if (read_reg(TRNG_ACCUM_ADDR) != TRNG_ACCUM_CYCLES) {
        return false;
    }

    // Verify IDLE status
    status = read_reg(TRNG_STATUS_ADDR);

    if (status != TRNG_IDLE) {
        return false;
    }

    // Start acquisition
    write_reg(TRNG_CONTROL_ADDR, TRNG_START);

    // Poll STATUS until DONE
    timeout = TRNG_TIMEOUT;

    do {
        status = read_reg(TRNG_STATUS_ADDR);

        if (status == TRNG_DONE) {
            break;
        }

        timeout--;

    } while (timeout > 0);

    if (status != TRNG_DONE) {
        return false;
    }

    // Read random data
    *random_data = read_reg(TRNG_DATA_ADDR);

    return true;
}


// ============================================================
// Perform one timed TRNG measurement
// ============================================================

static bool trng_measure(trng_measurement_t *measurement)
{
    measurement->start_time = read_elapsed_time();

    if (!trng_acquire(&measurement->random_data)) {
        return false;
    }

    measurement->end_time = read_elapsed_time();

    measurement->delta_cycles =
        measurement->end_time - measurement->start_time;

    return true;
}


// ============================================================
// Display TRNG measurement
// ============================================================

static void display_trng_measurement(
    const trng_measurement_t *measurement)
{
    dprint("\r\nStart time:  ");
    print_hex64(measurement->start_time);

    dprint("\r\nEnd time:    ");
    print_hex64(measurement->end_time);

    dprint("\r\nDifference:  ");
    print_hex64(measurement->delta_cycles);

    dprint("\r\nTRNG data:   0x");
    uart_send_hex(measurement->random_data);

    dprint("\r\n");
}


// ============================================================
// Option 2 - TRNG single measurement
// ============================================================

static void test_trng_single(void)
{
    trng_measurement_t measurement;

    dprint("\r\n========== TRNG SINGLE MEASUREMENT ==========\r\n");

    while (1) {

        gpio_write(0x01);

        if (trng_measure(&measurement)) {

            gpio_write(0x02);

            display_trng_measurement(&measurement);

        } else {

            dprint("\r\nERROR: TRNG acquisition failed\r\n");
        }

        wait_uart_tx();

        if (!wait_for_next_measurement()) {
            break;
        }
    }
}


// ============================================================
// Count bits
// ============================================================

static uint32_t count_ones(uint32_t value)
{
    uint32_t count = 0;

    for (int i = 0; i < 32; i++) {
        count += (value >> i) & 1U;
    }

    return count;
}


// ============================================================
// Option 3 - TRNG automatic cumulative statistics
// ============================================================

static void test_trng_statistics(void)
{
    uint64_t total_ones = 0;
    uint64_t total_zeros = 0;
    uint64_t total_cycles = 0;

    uint64_t total_completed = 0;
    uint64_t total_errors = 0;

    uint64_t start_time;
    uint64_t end_time;
    uint64_t delta_cycles;

    uint32_t random_data;
    uint32_t ones;
    uint32_t zeros;

    uint32_t batch_completed;
    uint32_t batch_errors;

    uint32_t ones_pct;
    uint32_t zeros_pct;

    dprint("\r\n========== TRNG CUMULATIVE STATISTICS ==========\r\n");

    // Counters are initialized only when entering option 3.
    // Each Enter adds another batch of acquisitions.

    while (1) {

        batch_completed = 0;
        batch_errors = 0;

        gpio_write(0x03);

        dprint("\r\nStarting TRNG acquisition batch...\r\n");
        dprint("Acquisitions per batch: %d\r\n",
               (int)TRNG_TEST_ITERATIONS);

        wait_uart_tx();

        // -----------------------------------------
        // Capture batch start time
        // -----------------------------------------

        start_time = read_elapsed_time();

        // -----------------------------------------
        // Automatic acquisition loop
        // -----------------------------------------

        for (uint32_t i = 0; i < TRNG_TEST_ITERATIONS; i++) {

            if (!trng_acquire(&random_data)) {

                batch_errors++;
                break;
            }

            // Count bits in the 32-bit result
            ones = count_ones(random_data);
            zeros = 32U - ones;

            // Update cumulative statistics
            total_ones += ones;
            total_zeros += zeros;

            batch_completed++;
        }

        // -----------------------------------------
        // Capture batch end time
        // -----------------------------------------

        end_time = read_elapsed_time();

        delta_cycles = end_time - start_time;

        // Accumulate completed acquisitions, errors and time
        total_completed += batch_completed;
        total_errors += batch_errors;
        total_cycles += delta_cycles;

        gpio_write(0x04);

        // -----------------------------------------
        // Display batch results
        // -----------------------------------------

        dprint("\r\n========== TRNG BATCH RESULTS ==========\r\n");

        dprint("Batch acquisitions: %d\r\n",
               (int)batch_completed);

        dprint("Batch errors: %d\r\n",
               (int)batch_errors);

        dprint("\r\nBatch start time: ");
        print_hex64(start_time);

        dprint("\r\nBatch end time:   ");
        print_hex64(end_time);

        dprint("\r\nBatch cycles:     ");
        print_hex64(delta_cycles);

        // -----------------------------------------
        // Display cumulative statistics
        // -----------------------------------------

        dprint("\r\n\r\n========== CUMULATIVE STATISTICS ==========\r\n");

        dprint("Total acquisitions: ");
        print_hex64(total_completed);

        dprint("\r\nTotal errors:       ");
        print_hex64(total_errors);

        dprint("\r\nTotal cycles:       ");
        print_hex64(total_cycles);

        dprint("\r\nTotal ones:         ");
        print_hex64(total_ones);

        dprint("\r\nTotal zeros:        ");
        print_hex64(total_zeros);

        dprint("\r\nTotal bits:         ");
        print_hex64(total_ones + total_zeros);

        dprint("\r\n");

        // -----------------------------------------
        // Calculate percentages
        // -----------------------------------------

        uint64_t total_bits = total_ones + total_zeros;

        if (total_bits != 0) {

            /*
             * Calculate percentages without multiplication.
             *
             * We divide by the total number of acquisitions,
             * since each acquisition contains 32 bits.
             *
             * Percentage calculations use integer division.
             */

            uint64_t ones_percent =
                total_ones / total_completed;

            uint64_t zeros_percent =
                total_zeros / total_completed;

            /*
             * The above gives the average number of ones
             * and zeros per 32-bit word, not a percentage.
             * For an actual percentage without multiplication,
             * use repeated addition or a separate algorithm.
             *
             * We display average bit counts instead.
             */

            dprint("\r\nAverage ones per word:  %d\r\n",
                   (int)ones_percent);

            dprint("Average zeros per word: %d\r\n",
                   (int)zeros_percent);
        }

        dprint("\r\n========================================\r\n");

        if (batch_errors != 0) {
            dprint("WARNING: Batch stopped due to acquisition error\r\n");
        } else {
            dprint("Batch completed successfully\r\n");
        }

        wait_uart_tx();

        // -----------------------------------------
        // Run another batch or return to menu
        // -----------------------------------------

        if (!wait_for_next_measurement()) {
            break;
        }
    }
}


// ============================================================
// Main menu
// ============================================================

static void show_menu(void)
{
    dprint("\r\n");
    dprint("========== FPGA TEST MENU ==========\r\n");
    dprint("1. FPGA / Firmware Information\r\n");
    dprint("2. TRNG Single Measurement\r\n");
    dprint("3. TRNG Cumulative Bit Statistics\r\n");
    dprint("====================================\r\n");
    dprint("Select an option (1-3): ");

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
                test_trng_single();
                break;

            case '3':
                gpio_write(0x03);
                test_trng_statistics();
                break;

            default:
                dprint("\r\nInvalid option. Please select 1, 2 or 3.\r\n");
                break;
        }
    }

    return 0;
}