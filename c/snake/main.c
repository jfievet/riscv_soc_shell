#include <stdint.h>
#include <stdbool.h>

#include "generated_header.h"
#include "../common/common_lib.h"

/* Match these dimensions to the calibrated PuTTY window. */

#define X 80
#define Y 24
#define FPS 10U

#define BOARD_WIDTH  (X - 2)
#define BOARD_HEIGHT (Y - 3) /* Two borders and one status line. */
#define BOARD_CELLS  (BOARD_WIDTH * BOARD_HEIGHT)
#define INITIAL_LENGTH 3U
#define RX_BUDGET 32U

#define UART_TX_LEVEL_ADDR (UART_TX_ADDR + 0x8U)
#define TIME_FREQ_ADDR 0x0030000CU
#define TIME_LOW_ADDR  0x00300010U
#define TIME_HIGH_ADDR 0x00300014U

#if X < 8 || X > 255 || Y < 6 || Y > 255
#error "Snake requires 8 <= X <= 255 and 6 <= Y <= 255"
#endif
#if FPS == 0
#error "FPS must be greater than zero"
#endif

/* Opposite directions differ by bit 1. */
typedef enum {
    RIGHT = 0, DOWN = 1, LEFT = 2, UP = 3
} direction_t;

typedef enum {
    WAIT_START, PLAYING, WAIT_RESTART
} game_state_t;

typedef enum {
    STEP_OK, STEP_LOST, STEP_WON
} step_result_t;

/* Static storage: 13,834 bytes for these three arrays at 157 x 45. */
static uint8_t snake_x[BOARD_CELLS];
static uint8_t snake_y[BOARD_CELLS];
static uint8_t occupied[(BOARD_CELLS + 7U) / 8U];
static uint16_t head_index;
static uint16_t tail_index;
static uint16_t snake_length;
static uint8_t food_x;
static uint8_t food_y;
static direction_t direction;
static direction_t next_direction;
static bool turn_queued;
static bool skip_next_lf;
static uint32_t random_state;

static const char controls[] = "4:left 8:up 6:right 2:down";

static uint32_t read_reg(uint32_t address)
{
    return *(volatile uint32_t *)(uintptr_t)address;
}

static uint64_t read_elapsed_time(void)
{
    /* Reading frequency captures a coherent 64-bit counter in the RTL. */
    (void)read_reg(TIME_FREQ_ADDR);
    uint32_t low = read_reg(TIME_LOW_ADDR);
    uint32_t high = read_reg(TIME_HIGH_ADDR);
    return ((uint64_t)high << 32) | low;
}

static void wait_uart_tx(void)
{
    while (read_reg(UART_TX_LEVEL_ADDR) != 0U) {
    }
}

static bool uart_try_read(uint8_t *key)
{
    if (read_reg(UART_RX_LEVEL_ADDR) == 0U) {
        return false;
    }
    *key = (uint8_t)read_reg(UART_RX_DATA_ADDR);
    return true;
}

static void discard_pending_input(void)
{
    /* Drain a snapshot, not an unbounded stream of newly arriving bytes. */
    uint32_t pending = read_reg(UART_RX_LEVEL_ADDR);
    while (pending != 0U) {
        (void)read_reg(UART_RX_DATA_ADDR);
        --pending;
    }
    skip_next_lf = false;
}

static bool is_enter(uint8_t key)
{
    if (key == '\n' && skip_next_lf) {
        skip_next_lf = false;
        return false;
    }
    skip_next_lf = (key == '\r');
    return key == '\r' || key == '\n';
}

static void cursor_to(uint16_t row, uint16_t column)
{
    uart_send_str("\033[");
    uart_send_dec((int)row);
    uart_send_byte(';');
    uart_send_dec((int)column);
    uart_send_byte('H');
}

static void draw_cell(uint8_t x, uint8_t y, uint8_t symbol)
{
    /* Playfield coordinates start inside the border at terminal (2, 2). */
    cursor_to((uint16_t)y + 2U, (uint16_t)x + 2U);
    uart_send_byte(symbol);
}

static void status_text(const char *text, uint16_t *columns)
{
    /* Never write the bottom-right cell: it can scroll the terminal. */
    while (*text != '\0' && *columns < X - 1U) {
        uart_send_byte((uint8_t)*text++);
        ++*columns;
    }
}

static void show_status(const char *message, bool show_cursor, bool with_score)
{
    uint16_t columns = 0;
    char number[12];

    cursor_to(Y, 1);
    uart_send_str("\033[2K");
    if (with_score) {
        status_text("Score: ", &columns);
        int32_to_str((int)snake_length - (int)INITIAL_LENGTH, number);
        status_text(number, &columns);
        status_text(" | ", &columns);
    }
    status_text(message, &columns);
    uart_send_str(show_cursor ? "\033[?25h" : "\033[?25l");
}

static void draw_frame(void)
{
    uart_send_str("\033[?25l\033[2J\033[H");
    for (uint16_t row = 0; row < Y - 1U; ++row) {
        /* Absolute row positioning avoids newline/autowrap interactions. */
        cursor_to(row + 1U, 1);
        for (uint16_t column = 0; column < X; ++column) {
            bool edge_row = row == 0U || row == Y - 2U;
            bool edge_column = column == 0U || column == X - 1U;
            uint8_t ch = ' ';
            if (edge_row && edge_column) {
                ch = '+';
            } else if (edge_row) {
                ch = (uint8_t)('0' + column % 10U);
            } else if (edge_column) {
                ch = (uint8_t)('0' + row % 10U);
            }
            uart_send_byte(ch);
        }
    }
}

static uint32_t cell_index(uint8_t x, uint8_t y)
{
    return (uint32_t)y * BOARD_WIDTH + x;
}

static bool cell_occupied(uint32_t cell)
{
    return (occupied[cell >> 3] & (uint8_t)(1U << (cell & 7U))) != 0U;
}

static void set_cell(uint8_t x, uint8_t y, bool value)
{
    uint32_t cell = cell_index(x, y);
    uint8_t mask = (uint8_t)(1U << (cell & 7U));
    if (value) {
        occupied[cell >> 3] |= mask;
    } else {
        occupied[cell >> 3] &= (uint8_t)~mask;
    }
}

static uint16_t next_index(uint16_t index)
{
    ++index;
    return index == BOARD_CELLS ? 0U : index;
}

static uint32_t random_next(void)
{
    uint32_t value = random_state;
    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    random_state = value;
    return value;
}

static bool place_food(void)
{
    if (snake_length == BOARD_CELLS) {
        return false;
    }

    /* Random starting cell, then a bounded scan: no rejection-loop hang
       when almost every cell is occupied. Uniform distribution is not needed. */
    uint32_t cell = random_next() % BOARD_CELLS;
    for (uint32_t checked = 0; checked < BOARD_CELLS; ++checked) {
        if (!cell_occupied(cell)) {
            food_y = (uint8_t)(cell / BOARD_WIDTH);
            food_x = (uint8_t)(cell % BOARD_WIDTH);
            draw_cell(food_x, food_y, '*');
            return true;
        }
        ++cell;
        if (cell == BOARD_CELLS) {
            cell = 0;
        }
    }
    return false;
}

static void start_round(void)
{
    for (uint32_t i = 0; i < sizeof occupied; ++i) {
        occupied[i] = 0;
    }
    head_index = INITIAL_LENGTH - 1U;
    tail_index = 0;
    snake_length = INITIAL_LENGTH;
    direction = RIGHT;
    next_direction = RIGHT;
    turn_queued = false;

    uint64_t seed = read_elapsed_time();
    random_state = (uint32_t)seed ^ (uint32_t)(seed >> 32) ^ 0x9E3779B9U;
    if (random_state == 0U) {
        random_state = 1U;
    }

    draw_frame();
    uint8_t center_x = BOARD_WIDTH / 2U;
    uint8_t center_y = BOARD_HEIGHT / 2U;
    for (uint16_t i = 0; i < INITIAL_LENGTH; ++i) {
        snake_x[i] = (uint8_t)(center_x - (INITIAL_LENGTH - 1U) + i);
        snake_y[i] = center_y;
        set_cell(snake_x[i], snake_y[i], true);
        draw_cell(snake_x[i], snake_y[i], i == head_index ? '@' : 'o');
    }
    (void)place_food();
    show_status(controls, false, true);
    /* Do not start the first movement while the full board is still queued. */
    wait_uart_tx();
}

static void queue_direction(uint8_t key)
{
    direction_t requested;
    switch (key) {
        case '4': requested = LEFT; break;
        case '8': requested = UP; break;
        case '6': requested = RIGHT; break;
        case '2': requested = DOWN; break;
        default: return;
    }
    if (turn_queued || requested == direction ||
        (unsigned int)requested == ((unsigned int)direction ^ 2U)) {
        return;
    }
    next_direction = requested;
    turn_queued = true;
}

static step_result_t step_game(void)
{
    static const int8_t dx[4] = {1, 0, -1, 0};
    static const int8_t dy[4] = {0, 1, 0, -1};
    uint8_t old_head_x = snake_x[head_index];
    uint8_t old_head_y = snake_y[head_index];
    uint8_t old_tail_x = snake_x[tail_index];
    uint8_t old_tail_y = snake_y[tail_index];

    direction = next_direction;
    turn_queued = false;
    int new_x = (int)old_head_x + dx[direction];
    int new_y = (int)old_head_y + dy[direction];
    if (new_x < 0 || new_x >= BOARD_WIDTH || new_y < 0 || new_y >= BOARD_HEIGHT) {
        return STEP_LOST;
    }

    uint8_t x = (uint8_t)new_x;
    uint8_t y = (uint8_t)new_y;
    bool grows = x == food_x && y == food_y;
    bool vacating_tail = !grows && x == old_tail_x && y == old_tail_y;
    if (cell_occupied(cell_index(x, y)) && !vacating_tail) {
        return STEP_LOST;
    }

    if (!grows) {
        set_cell(old_tail_x, old_tail_y, false);
        draw_cell(old_tail_x, old_tail_y, ' ');
        tail_index = next_index(tail_index);
    }
    draw_cell(old_head_x, old_head_y, 'o');
    head_index = next_index(head_index);
    snake_x[head_index] = x;
    snake_y[head_index] = y;
    set_cell(x, y, true);
    draw_cell(x, y, '@');

    if (grows) {
        ++snake_length;
        if (!place_food()) {
            return STEP_WON;
        }
        show_status(controls, false, true);
    }
    return STEP_OK;
}

int main(void)
{
    gpio_write(0x01);
    wait_uart_tx();
    discard_pending_input();
    draw_frame();

    uint32_t frequency = read_reg(TIME_FREQ_ADDR);
    if (frequency == 0U) {
        show_status("ERROR: time_elapsed frequency is zero", true, false);
        wait_uart_tx();
        return 0;
    }
    uint64_t frame_ticks = frequency / FPS;
    if (frame_ticks == 0U) {
        frame_ticks = 1U;
    }

    show_status("4:left 8:up 6:right 2:down | Press Enter to play", true, false);
    wait_uart_tx();
    gpio_write(0x02);
    game_state_t state = WAIT_START;
    uint64_t last_tick = read_elapsed_time();

    while (true) {
        for (uint32_t received = 0; received < RX_BUDGET; ++received) {
            uint8_t key;
            if (!uart_try_read(&key)) {
                break;
            }
            bool enter = is_enter(key);
            if (state != PLAYING) {
                if (enter) {
                    start_round();
                    state = PLAYING;
                    last_tick = read_elapsed_time();
                }
            } else {
                queue_direction(key);
            }
        }

        if (state == PLAYING) {
            uint64_t now = read_elapsed_time();
            if (now - last_tick >= frame_ticks) {
                /* Exactly one movement per iteration, never a catch-up loop. */
                last_tick = now;
                step_result_t result = step_game();
                if (result != STEP_OK) {
                    state = WAIT_RESTART;
                    discard_pending_input();
                    show_status(result == STEP_WON
                        ? "You win! Press Enter to play again"
                        : "Game over press enter pour rejouer", true, true);
                } else {
                    uint64_t after_render = read_elapsed_time();
                    if (after_render - now >= frame_ticks) {
                        last_tick = after_render;
                    }
                }
            }
        }
    }
}
