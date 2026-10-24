#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdbool.h>

#include "generated_header.h"
#include "../common/common_lib.h"


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

    while(1) {
        int a;
        int b;
        int c;

        dprint("\r\nEnter a:  \r\n");
        a = uart_read_int();

        dprint("Enter b:  \r\n");
        b = uart_read_int();

        c = a + b;

        dprint("Result: %d + %d = %d\r\n", a, b, c);

        while (*level_reg != 0) {
            gpio_write(0xFF);
        }
    }


    return 0;
}
