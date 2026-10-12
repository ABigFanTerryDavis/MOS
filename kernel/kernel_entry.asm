; First byte of the flat kernel image: 64-bit entry point at physical 0x100000.
[BITS 64]
section .text.entry
global _start
extern kernel_main

_start:
    mov rsp, 0x90000       ; protected-mode boot stack, 16-byte aligned
    xor rbp, rbp
    call kernel_main
.halt:
    cli
    hlt
    jmp .halt

section .note.GNU-stack noalloc noexec nowrite progbits
