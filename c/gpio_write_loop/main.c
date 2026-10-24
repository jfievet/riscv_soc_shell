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

    // The folowing send values on uart
    while(1){
        gpio_write(i);
        dprint("Value: %\n", i);
        i=i+1;
        while (*level_reg != 0) {
            // Wait until the level at addr 8 is not 0
        }
    }

    return 0;
}
