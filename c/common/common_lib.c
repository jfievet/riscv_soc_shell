#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdbool.h>

#include "common_lib.h"

// Helper: send a single char to UART
void uart_send_byte(uint8_t byte) {
    volatile uint8_t *uart_tx = (volatile uint8_t *)UART_TX_ADDR;
    *uart_tx = byte;
}

// Helper: send a string to UART
void uart_send_str(const char *str) {
    while (*str) uart_send_byte(*str++);
}

void int32_to_str(int n, char *str) {
    int pos = 0;
    int d;
    int started = 0;

    if (n == 0) { str[0] = '0'; str[1] = '\0'; return; }

    d = 0; while (n >= 1000000000) { n -= 1000000000; d++; asm volatile(""); } if (d || started) { str[pos++] = '0' + d; started = 1; }
    d = 0; while (n >= 100000000)  { n -= 100000000;  d++; asm volatile(""); } if (d || started) { str[pos++] = '0' + d; started = 1; }
    d = 0; while (n >= 10000000)   { n -= 10000000;   d++; asm volatile(""); } if (d || started) { str[pos++] = '0' + d; started = 1; }
    d = 0; while (n >= 1000000)    { n -= 1000000;    d++; asm volatile(""); } if (d || started) { str[pos++] = '0' + d; started = 1; }
    d = 0; while (n >= 100000)     { n -= 100000;     d++; asm volatile(""); } if (d || started) { str[pos++] = '0' + d; started = 1; }
    d = 0; while (n >= 10000)      { n -= 10000;      d++; asm volatile(""); } if (d || started) { str[pos++] = '0' + d; started = 1; }
    d = 0; while (n >= 1000)       { n -= 1000;       d++; asm volatile(""); } if (d || started) { str[pos++] = '0' + d; started = 1; }
    d = 0; while (n >= 100)        { n -= 100;        d++; asm volatile(""); } if (d || started) { str[pos++] = '0' + d; started = 1; }
    d = 0; while (n >= 10)         { n -= 10;         d++; asm volatile(""); } if (d || started) { str[pos++] = '0' + d; started = 1; }
    str[pos++] = '0' + n;
    str[pos] = '\0';
}

// Helper: convert int to decimal string and send
void uart_send_dec(int value) {
    char buf[12];
    int tmp_value;

    if (value == 0) {
        uart_send_byte('0');
        return;
    }

    if (value < 0) {
        uart_send_byte('-');
        tmp_value =(-value);
    } else {
        tmp_value =value;
    }

    int32_to_str(tmp_value, buf);
    uart_send_str(buf);
}

// Helper: convert int to hex string and send
void uart_send_hex(unsigned int value) {
    for (int i = 7; i >= 0; i--) {
        int digit = (value >> (i * 4)) & 0xF;
        uart_send_byte(digit < 10 ? '0' + digit : 'A' + digit - 10);
    }
}

// Adapted dprint
void dprint(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);

    while (*fmt) {
        if (*fmt == '%') {
            fmt++;
            switch (*fmt) {
                case 'd':
                    uart_send_dec(va_arg(args, int));
                    break;
                case 'l':
                    uart_send_dec(va_arg(args, long));
                    break;
                case 'x':
                    uart_send_hex(va_arg(args, unsigned int));
                    break;
                case 's':
                    uart_send_str(va_arg(args, char *));
                    break;
                case '%':
                    uart_send_byte('%');
                    break;
                default:
                    uart_send_byte('%');
                    uart_send_byte(*fmt);
                    break;
            }
        } else {
            uart_send_byte(*fmt);
        }
        fmt++;
    }
    va_end(args);
}

// Waits for a byte in the UART RX FIFO and returns it
uint8_t dget(void) {
    volatile uint32_t *rx_level = (volatile uint32_t *)UART_RX_LEVEL_ADDR;
    volatile uint32_t *rx_data  = (volatile uint32_t *)UART_RX_DATA_ADDR;
    // Wait until RX FIFO has data
    while (*rx_level == 0) {
        // Busy wait
    }
    // Read and return the received byte
    return (uint8_t)(*rx_data & 0xFF);
}

// Read ASCII digits from the terminal until Enter is pressed, convert that to a signed
int uart_read_int(void) {
    int value = 0;
    bool negative = false;
    bool have_digit = false;

    while (1) {
        uint8_t ch = dget();

        if (ch == '\r' || ch == '\n') {
            if (have_digit) {
                uart_send_byte('\r');
                uart_send_byte('\n');
                return negative ? -value : value;
            }
            continue;
        }

        if (!have_digit && !negative && ch == '-') {
            negative = true;
            uart_send_byte(ch);  // echo
            continue;
        }

        if (ch >= '0' && ch <= '9') {
            have_digit = true;
            value = value * 10 + (ch - '0');
            uart_send_byte(ch);  // echo
        }
    }
}

// Simulate writing to a memory-mapped GPIO register
void gpio_write(uint32_t value) {
    volatile uint32_t *gpio = (volatile uint32_t *)GPIO_BASE_ADDR;
    *gpio = value;
}

uint32_t uart_read_u32_be(void)
{
    uint32_t value = 0;

    value |= ((uint32_t)dget()) << 24;
    value |= ((uint32_t)dget()) << 16;
    value |= ((uint32_t)dget()) << 8;
    value |= ((uint32_t)dget()) << 0;

    return value;
}

void uart_send_u32_be(uint32_t value)
{
    uart_send_byte((uint8_t)((value >> 24) & 0xFF));
    uart_send_byte((uint8_t)((value >> 16) & 0xFF));
    uart_send_byte((uint8_t)((value >> 8) & 0xFF));
    uart_send_byte((uint8_t)(value & 0xFF));
}