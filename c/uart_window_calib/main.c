
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include "generated_header.h"
#include "../common/common_lib.h"

/* ============================================
 * UART TERMINAL CALIBRATION
 * ============================================ */

// Putty default conf
//#define X  80   // Number of columns
//#define Y  24   // Number of rows

//Putty full screen
#define X  157   // Number of columns
#define Y  45   // Number of rows



/* ============================================
 * MAIN
 * ============================================ */

int main(void)
{
    volatile uint32_t *level_reg =
        (volatile uint32_t *)(UART_TX_ADDR + 8);

    char str[2] = {0, 0};

    gpio_write(0x01);

    // Wait until UART TX is empty
    while (*level_reg != 0) {
    }

    // Clear terminal and move cursor to top-left
    dprint("\033[2J\033[H");

    // Print calibration rectangle
    for (int y = 0; y < Y; y++) {

        for (int x = 0; x < X; x++) {

            if ((y == 0 || y == Y - 1) &&
                (x == 0 || x == X - 1)) {

                dprint("+");

            } else if (y == 0 || y == Y - 1) {

                // Horizontal X coordinate (modulo 10)
                str[0] = '0' + (x % 10);
                dprint("%s", str);

            } else if (x == 0 || x == X - 1) {

                // Vertical Y coordinate (modulo 10)
                str[0] = '0' + (y % 10);
                dprint("%s", str);

            } else {

                dprint(" ");
            }
        }

        // CR + LF except on last row
        if (y < Y - 1) {
            dprint("\r\n");
        }
    }

    // Wait until all characters are transmitted
    while (*level_reg != 0) {
    }

    gpio_write(0x02);

    while (1) {
        // Calibration display remains static
    }

    return 0;
}
