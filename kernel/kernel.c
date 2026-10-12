#include "vga.h"

/* VGA text memory is identity-mapped by stage 2. No libc or BIOS calls. */
static void hide_cursor(void) {
    /* CRTC index 0x0A, bit 5 disables the legacy blinking cursor. */
    __asm__ volatile ("outb %0, %1" : : "a"((uint8_t)0x0A), "Nd"((uint16_t)0x3D4));
    __asm__ volatile ("outb %0, %1" : : "a"((uint8_t)0x20), "Nd"((uint16_t)0x3D5));
}

static void fill_row(int row, char ch, uint8_t color) {
    for (int x = 0; x < VGA_WIDTH; ++x) {
        vga_cell(x, row, ch, color);
    }
}

static void text(int x, int y, const char *message, uint8_t color) {
    while (*message && x < VGA_WIDTH) {
        vga_cell(x++, y, *message++, color);
    }
}

static void centered(int y, const char *message, uint8_t color) {
    int length = 0;
    while (message[length]) ++length;
    text((VGA_WIDTH - length) / 2, y, message, color);
}

void kernel_main(void) {
    const uint8_t bg = vga_color(15, 1);       /* white on blue */
    const uint8_t accent = vga_color(11, 1);   /* cyan on blue */
    const uint8_t muted = vga_color(7, 1);     /* light grey on blue */
    const uint8_t green = vga_color(10, 1);   /* light green on blue */

    hide_cursor();
    for (int y = 0; y < VGA_HEIGHT; ++y) fill_row(y, ' ', bg);
    fill_row(0, ' ', vga_color(15, 3));        /* top cyan bar */
    text(3, 0, "MOS", vga_color(15, 3));
    text(64, 0, "MILESTONE 01", vga_color(15, 3));

    centered(4, "M O S", accent);
    centered(5, "a tiny x86-64 operating system", muted);
    centered(7, "========================================", accent);

    text(16, 9,  "STAGE 1", bg);
    text(33, 9,  "custom BIOS boot sector", muted);
    text(63, 9,  "[ OK ]", green);
    text(16, 11, "STAGE 2", bg);
    text(33, 11, "real -> protected -> long", muted);
    text(63, 11, "[ OK ]", green);
    text(16, 13, "KERNEL", bg);
    text(33, 13, "64-bit C at 0x100000", muted);
    text(63, 13, "[ OK ]", green);
    text(16, 15, "DISPLAY", bg);
    text(33, 15, "VGA text at 0xB8000", muted);
    text(63, 15, "[ OK ]", green);

    centered(18, "BOOT SUCCESSFUL", green);
    centered(21, "NASM  +  C  |  64-bit long mode  |  no GRUB", accent);
    centered(23, "MOS / first light", muted);

    /* Until we have interrupts and an event loop, stay here forever. */
    for (;;) __asm__ volatile ("hlt");
}
