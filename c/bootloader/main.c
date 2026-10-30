#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdbool.h>

#include "generated_header.h"
#include "../common/common_lib.h"

#define _DEBUG_ 1;

typedef void (*entry_fn_t)(void);
#define APP_BASE 0x00001000u


int main(void) {

    int debug = _DEBUG_;

    volatile uint32_t *level_reg = (volatile uint32_t *)(UART_TX_ADDR + 8);
    int i=0;
    uint8_t received;

    if (debug) gpio_write(0x01);

    //The following display the version
    volatile uint32_t *reg0 = (volatile uint32_t *)AXI_SLAVE_REG_REG0;
    volatile uint32_t *reg1 = (volatile uint32_t *)AXI_SLAVE_REG_REG1;

    uint32_t reg0_val = *reg0;
    uint32_t reg1_val = *reg1;

    if (debug) gpio_write(0x02);

    int day    = (int)(reg0_val & 0xFF);
    int month  = (int)((reg0_val >> 8) & 0xFF);
    int year   = (int)((reg0_val >> 16) & 0xFFFF);

    uint8_t hour   = reg1_val & 0xFF;
    uint8_t minute = (reg1_val >> 8) & 0xFF;
    uint8_t second = (reg1_val >> 16) & 0xFF;

    if (debug) gpio_write(0x1);

    dprint("FPGA date: %d/%d/%d \r\n", day, month, year);
    while (*level_reg != 0) {
        // Wait until the value at UART_TX_ADDR + 8 is 0
        if (debug) gpio_write(0xFF);
    }
    if (debug) gpio_write(0x2);
    //
    dprint("FPGA time: %d:%d:%d \r\n", hour, minute, second);
    while (*level_reg != 0) {
        // Wait until the value at UART_TX_ADDR + 8 is 0
        if (debug) gpio_write(0xFF);
    }
    if (debug) gpio_write(0x3);
    //
    dprint("Elf date: %d/%d/%d \r\n", generated_year, generated_month, generated_day);
    while (*level_reg != 0) {
        // Wait until the value at UART_TX_ADDR + 8 is 0
        if (debug) gpio_write(0xFF);
    }
    if (debug) gpio_write(0x4);
    //
    dprint("Elf time: %d:%d:%d \r\n", generated_hour, generated_minute, generated_second);
    while (*level_reg != 0) {
        // Wait until the value at UART_TX_ADDR + 8 is 0
        if (debug) gpio_write(0xFF);
    }
    if (debug) gpio_write(0x5);
    //
    dprint("Bootloader ready \r\n");
    while (*level_reg != 0) {
        // Wait until the value at UART_TX_ADDR + 8 is 0
        if (debug) gpio_write(0xFF);
    }
    if (debug) gpio_write(0x6);


    uint32_t app_base = APP_BASE;

    while (1) {
        uint8_t sync;
        uint32_t addr;
        uint32_t data;
        volatile uint32_t *target;

        // Wait for a supported command byte.
        if (debug) gpio_write(0x7);
        do {
            if (debug) gpio_write(0x8);
            sync = dget();
            if (debug) gpio_write(0x9);
        } while (sync != 0xAA && sync != 0x55 && sync != 0xBB);

        if (sync == 0xBB) {
            // Configure the jump address without writing to memory.
            addr = uart_read_u32_be();
            data = uart_read_u32_be();

            if (addr == 0U) {
                app_base = data;
            }

            // Return the received address and the effective jump base.
            uart_send_byte(0xBB);
            uart_send_u32_be(addr);
            uart_send_u32_be(app_base);
            while (*level_reg != 0) {
                if (debug) gpio_write(0xFF);
            }
        }

        if (sync == 0xAA) {
            if (debug) gpio_write(0x10);

            // Receive ADDR and DATA
            addr = uart_read_u32_be();
            data = uart_read_u32_be();

            if (debug) gpio_write(0x11);

            // Write DATA to ADDR
            target = (volatile uint32_t *)addr;
            *target = data;

            if (debug) gpio_write(0x12);

            // Acknowledge by echoing the received frame
            uart_send_byte(0xAA);
            if (debug) gpio_write(0x13);
            uart_send_u32_be(addr);
            if (debug) gpio_write(0x14);
            uart_send_u32_be(data);

            while (*level_reg != 0) {
                if (debug) gpio_write(0xFF);
            }

            if (debug) gpio_write(0x15);
        } //end if

        if (sync == 0x55) {
            uint8_t ch;

            if (debug) gpio_write(0x20);
            // Receive ADDR and DATA
            addr = uart_read_u32_be();
            data = uart_read_u32_be();
            if (debug) gpio_write(0x21);
            // Write DATA to ADDR
            target = (volatile uint32_t *)addr;
            *target = data;
            if (debug) gpio_write(0x22);
            // Acknowledge by echoing the received frame
            uart_send_byte(0xAA);
            if (debug) gpio_write(0x23);
            uart_send_u32_be(addr);
            if (debug) gpio_write(0x24);
            uart_send_u32_be(data);
            while (*level_reg != 0) {
                if (debug) gpio_write(0xFF);
            }
            if (debug) gpio_write(0x25);

            dprint("Press y to jump\r\n");
            while (*level_reg != 0) {
                if (debug) gpio_write(0xFF);
            }

            ch = dget();  // returns as soon as one byte is received

            if (ch == 0x79) {
                entry_fn_t app_entry = (entry_fn_t)app_base;
                app_entry();
            }
        }

        if (debug) gpio_write(0x17);

    } // endwhile

        if (debug) gpio_write(0x99);

    return 0;
}
