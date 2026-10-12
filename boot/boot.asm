; MOS stage 1: BIOS loads this 512-byte sector at physical 0x7C00.
; Read eight sectors (stage 2) from LBA 1 into 0000:7E00.
[BITS 16]
[ORG 0x7C00]

STAGE2_SECTORS equ 8

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    mov [boot_drive], dl

    ; INT 13h extensions (EDD): DS:SI points to a 16-byte disk address packet.
    mov si, stage2_dap
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jc disk_error
    mov dl, [boot_drive]
    jmp 0x0000:0x7E00

disk_error:
    mov si, error_message
.print:
    lodsb
    test al, al
    jz .hang
    mov ah, 0x0E
    xor bx, bx
    int 0x10
    jmp .print
.hang:
    cli
    hlt
    jmp .hang

boot_drive db 0
error_message db 'MOS: stage 2 read failed', 0
stage2_dap:
    db 0x10, 0            ; packet size, reserved
    dw STAGE2_SECTORS     ; number of 512-byte sectors
    dw 0x7E00, 0x0000     ; destination offset:segment
    dq 1                 ; stage 2 starts at LBA 1

times 510-($-$$) db 0
dw 0xAA55
