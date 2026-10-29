#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdbool.h>

#include "generated_header.h"
#include "../common/common_lib.h"

static uint64_t read_elapsed_time(void)
{
    volatile uint32_t *reg_freq = (volatile uint32_t *)0x0030000C;
    volatile uint32_t *reg_low  = (volatile uint32_t *)0x00300010;
    volatile uint32_t *reg_high = (volatile uint32_t *)0x00300014;

    // Read frequency register first to trigger counter capture
    uint32_t freq = *reg_freq;
    (void)freq;

    // Read captured 64-bit counter
    uint32_t low  = *reg_low;
    uint32_t high = *reg_high;

    return ((uint64_t)high << 32) | low;
}


int main(void) {

    volatile uint32_t *level_reg = (volatile uint32_t *)(UART_TX_ADDR + 8);
    int i=0;
    uint8_t received;

    gpio_write(0x01);

    //The following display the version
    volatile uint32_t *reg0 = (volatile uint32_t *)AXI_SLAVE_REG_REG0;
    volatile uint32_t *reg1 = (volatile uint32_t *)AXI_SLAVE_REG_REG1;

    uint32_t reg0_val = *reg0;
    uint32_t reg1_val = *reg1;

    gpio_write(0x02);

    int day    = (int)(reg0_val & 0xFF);
    int month  = (int)((reg0_val >> 8) & 0xFF);
    int year   = (int)((reg0_val >> 16) & 0xFFFF);

    uint8_t hour   = reg1_val & 0xFF;
    uint8_t minute = (reg1_val >> 8) & 0xFF;
    uint8_t second = (reg1_val >> 16) & 0xFF;

    gpio_write(0x1);

    dprint("FPGA build date: %d/%d/%d \r\n", day, month, year);
    while (*level_reg != 0) {
        // Wait until the value at UART_TX_ADDR + 8 is 0
        gpio_write(0xFF);
    }
    gpio_write(0x2);

    dprint("FPGA build time: %d:%d:%d \r\n", hour, minute, second);
    while (*level_reg != 0) {
        // Wait until the value at UART_TX_ADDR + 8 is 0
        gpio_write(0xFF);
    }
    gpio_write(0x3);

    dprint("Elf build date: %d/%d/%d \r\n", generated_day, generated_month, generated_year);
    while (*level_reg != 0) {
        // Wait until the value at UART_TX_ADDR + 8 is 0
        gpio_write(0xFF);
    }
    gpio_write(0x4);

    dprint("Elf build time: %d:%d:%d \r\n", generated_hour, generated_minute, generated_second);
    while (*level_reg != 0) {
        // Wait until the value at UART_TX_ADDR + 8 is 0
        gpio_write(0xFF);
    }
    gpio_write(0x5);

    volatile uint32_t *test_reg = (volatile uint32_t *)0x300008;
    volatile uint32_t *freq_reg = (volatile uint32_t *)0x30000C;
    uint32_t sys_freq = *freq_reg;
    dprint("FPGA system frequency: %d Hz\r\n", (int)sys_freq);

    while (1) {

        uint64_t start_time;
        uint64_t end_time;
        uint64_t delta_cycles;

        // Capture start time
        start_time = read_elapsed_time();

        dprint("Start 10e6 writes\r\n");

        // Perform 100 million writes
        for (uint32_t i = 0; i < 10000000U; i++) {
            *test_reg = 0x12345678;
        }

        // Capture end time
        end_time = read_elapsed_time();

        // Calculate elapsed cycles
        delta_cycles = end_time - start_time;

        dprint("100e6 writes done\r\n");

        dprint("Elapsed cycles: 0x");
        uart_send_hex((uint32_t)(delta_cycles >> 32));  // Upper 32 bits
        uart_send_hex((uint32_t)delta_cycles);          // Lower 32 bits
        dprint("\r\n");
        
    }

    return 0;
}
