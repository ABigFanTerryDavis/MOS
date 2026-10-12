; MOS stage 2: load C kernel below 1 MiB via BIOS, then enter long mode.
; Built with -DKERNEL_SECTORS=<1..127>; LBA 9 follows the 8-sector stage 2.
[BITS 16]
[ORG 0x7E00]

%ifndef KERNEL_SECTORS
    %error "Pass -DKERNEL_SECTORS=<count> to NASM"
%endif
%if KERNEL_SECTORS < 1 || KERNEL_SECTORS > 127
    %error "Kernel must fit in 1..127 sectors (at most 65024 bytes)"
%endif

KERNEL_BUFFER equ 0x10000
KERNEL_BASE   equ 0x100000
PML4          equ 0x70000
PDPT          equ 0x71000
PD            equ 0x72000
STACK_TOP     equ 0x90000

stage2_start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    mov [boot_drive], dl

    ; BIOS can read into conventional memory, not directly to 0x100000.
    ; This transfer stays entirely inside a single 64 KiB segment.
    mov si, kernel_dap
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jc disk_error

    ; Enable A20 via the fast A20 gate so 1 MiB no longer aliases 0.
    in al, 0x92
    or al, 00000010b
    and al, 11111110b
    out 0x92, al

    cli
    lgdt [gdt_descriptor]
    mov eax, cr0
    or eax, 1               ; CR0.PE: protected mode
    mov cr0, eax
    jmp 0x08:protected_mode  ; flush prefetch, use 32-bit code descriptor

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
error_message db 'MOS: kernel read failed', 0
kernel_dap:
    db 0x10, 0
    dw KERNEL_SECTORS
    dw 0, KERNEL_BUFFER >> 4 ; 1000:0000 = physical 0x10000
    dq 9                     ; sector 0 + 8 stage-2 sectors

align 8
gdt:
    dq 0                       ; null selector 0x00
    dq 0x00CF9A000000FFFF      ; 32-bit flat code selector 0x08
    dq 0x00CF92000000FFFF      ; flat data selector 0x10
    dq 0x00AF9A000000FFFF      ; 64-bit flat code selector 0x18 (L=1, D=0)
gdt_end:
gdt_descriptor:
    dw gdt_end - gdt - 1
    dd gdt

[BITS 32]
protected_mode:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, STACK_TOP
    cld

    ; Relocate kernel from BIOS read buffer to its linked address at 1 MiB.
    mov esi, KERNEL_BUFFER
    mov edi, KERNEL_BASE
    mov ecx, (KERNEL_SECTORS * 512) / 4
    rep movsd

    ; Three zeroed 4 KiB tables. First 1 GiB identity mapped with 2 MiB pages.
    mov edi, PML4
    xor eax, eax
    mov ecx, (3 * 4096) / 4
    rep stosd
    mov dword [PML4], PDPT | 3   ; present, writable
    mov dword [PDPT], PD | 3
    mov edi, PD
    mov eax, 0x83                ; present | writable | 2 MiB page
    mov ecx, 512
.map_pages:
    mov [edi], eax
    add edi, 8
    add eax, 0x200000           ; next 2 MiB physical page
    loop .map_pages

    mov eax, cr4
    or eax, 1 << 5             ; CR4.PAE
    mov cr4, eax
    mov eax, PML4
    mov cr3, eax
    mov ecx, 0xC0000080         ; IA32_EFER MSR
    rdmsr
    or eax, 1 << 8             ; EFER.LME: enable long mode
    wrmsr
    mov eax, cr0
    or eax, 1 << 31            ; CR0.PG: enable paging, activate long mode
    mov cr0, eax
    jmp 0x18:long_mode         ; load 64-bit code segment

[BITS 64]
long_mode:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, STACK_TOP
    mov rax, KERNEL_BASE
    jmp rax                     ; first byte is kernel _start

; Fixed-size stage 2 keeps kernel start at LBA 9, independent of code changes.
times 8*512-($-$$) db 0
