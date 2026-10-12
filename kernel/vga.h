#ifndef MOS_VGA_H
#define MOS_VGA_H

#include <stdint.h>

#define VGA_WIDTH 80
#define VGA_HEIGHT 25
#define VGA_MEMORY ((volatile uint16_t *)0xB8000)

static inline uint8_t vga_color(uint8_t foreground, uint8_t background) {
    return (uint8_t)(foreground | (background << 4));
}

static inline void vga_cell(int x, int y, char ch, uint8_t color) {
    VGA_MEMORY[y * VGA_WIDTH + x] = (uint16_t)(uint8_t)ch | ((uint16_t)color << 8);
}

#endif
