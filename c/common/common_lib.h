#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdbool.h>

#define UART_TX_ADDR    0x00100000
#define GPIO_BASE_ADDR  0x00200000
#define AXI_SLAVE_REG   0x00300000

#define UART_RX_DATA_ADDR   (UART_TX_ADDR + 0x4)
#define UART_RX_LEVEL_ADDR  (UART_TX_ADDR + 0xC)

#define AXI_SLAVE_REG_REG0   0x00300000
#define AXI_SLAVE_REG_REG1  (AXI_SLAVE_REG_REG0 + 0x4)

void uart_send_byte(uint8_t byte);

void uart_send_str(const char *str);

void int32_to_str(int n, char *str);

void uart_send_dec(int value);

void uart_send_hex(unsigned int value);

void dprint(const char *fmt, ...);

uint8_t dget(void);

int uart_read_int(void);

void gpio_write(uint32_t value);

uint32_t uart_read_u32_be(void);

void uart_send_u32_be(uint32_t value);