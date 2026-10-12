# MOS — a tiny x86-64 operating system

Custom bootloader, written in **NASM assembly** (boot) + **C** (kernel).
Target: `qemu-system-x86_64`. First milestone: **boot into 64-bit long mode and print colored text to the screen.**

---

## Why two bootloader stages?

The BIOS loads exactly one 512-byte sector (the MBR) at `0x7C00` and starts it in
**16-bit real mode**. Reaching 64-bit long mode requires: enabling A20, building a
GDT, switching to 32-bit protected mode, building 4-level page tables, enabling
PAE + EFER.LME + paging, then a far jump to a 64-bit code segment. That does **not**
fit in 512 bytes. So:

- **Stage 1** (`boot.asm`, 512 B): reads more sectors off disk and jumps to Stage 2.
- **Stage 2** (`stage2.asm`): does the real-mode → protected-mode → long-mode dance,
  loads the kernel into memory, and jumps into it.

---

## Memory map (physical)

| Address        | What lives there                       |
|---------------|----------------------------------------|
| `0x0000_7C00` | Stage 1 boot sector (loaded by BIOS)   |
| `0x0000_7E00` | Stage 2 bootloader (loaded by Stage 1) |
| `0x0001_0000` | BIOS kernel read buffer (up to 65024 B)|
| `0x0007_0000` | Page tables (PML4/PDPT/PD)             |
| `0x0009_0000` | Kernel stack top (grows downward)      |
| `0x0010_0000` | Kernel image (copied by Stage 2, 1 MiB)|

The first 1 GiB is **identity-mapped** with 2 MiB pages, so physical == virtual
addresses for the kernel at boot. The VGA text buffer at `0xB8000` is therefore
accessible directly — that's how we print text.

---

## The boot sequence, step by step

1. BIOS loads sector 0 (Stage 1) to `0x7C00`, CPU is in real mode.
2. **Stage 1** sets up a real-mode stack, uses BIOS INT 13h extensions to read
   eight sectors (LBA 1..8) into `0x7E00`, then jumps to Stage 2.
3. **Stage 2**:
   - Reads the kernel at LBA 9 into a low-memory buffer at `0x10000` (BIOS cannot
     read directly to 1 MiB). The build supplies its exact sector count.
   - Enables the A20 line.
   - Loads a 32-bit GDT, switches to **protected mode**.
   - Copies the kernel from `0x10000` to `0x100000`.
   - Builds page tables at `0x70000` (identity map first 1 GiB via 2 MiB pages).
   - Enables PAE (`CR4.PAE`), sets `EFER.LME`, enables paging (`CR0.PG`).
   - Far-jumps through the already-loaded GDT's 64-bit code descriptor.
   - Jumps to the kernel entry point at `0x100000`.
4. **Kernel** (`kernel_entry.asm` → `kernel.c`):
   - Sets up the 64-bit stack.
   - Calls `kernel_main()` in C.
   - Clears the VGA screen and writes colored text to `0xB8000`.
   - Halts.

---

## Project layout

```
MOS/
├── PLAN.md                # this file
├── Makefile               # build + run + test (qemu)
├── tests/smoke.py         # checks long-mode CPU state and VGA RAM
├── boot/
│   ├── boot.asm           # Stage 1: 512-byte MBR, loads stage2 + kernel
│   └── stage2.asm         # Stage 2: real -> protected -> long mode
├── kernel/
│   ├── kernel_entry.asm   # 64-bit entry stub, sets stack, calls main
│   ├── kernel.c           # C kernel: VGA text, main loop
│   ├── vga.h              # VGA buffer + color helpers
│   └── linker.ld          # link kernel at 0x100000
└── build/                 # generated images (os.img, *.bin, *.o)
```

---

## Build flow

```
make             # assembles, compiles, links, builds a 2 MiB raw disk image
make test        # boots QEMU, checks long-mode registers + VGA RAM, saves screenshot
make run         # starts QEMU with a graphical display
make clean       # removes generated files
```

The Makefile builds the kernel first so it can pass its exact sector count to
NASM when assembling Stage 2. It rejects kernels over 127 sectors (65,024 B),
the current one-call BIOS read limit. Booting requires BIOS INT 13h extensions
(EDD), which QEMU's BIOS provides. No GRUB, libc, or host OS code is linked.

```
# Optional manual run with a dedicated disk controller:
qemu-system-x86_64 -drive if=ide,format=raw,file=build/os.img -boot c -m 64M
```

---

## Milestone roadmap

- **M1 — Boot + text on screen (DONE)**
  Two-stage bootloader reaches 64-bit long mode; kernel prints colored text to VGA.
  `make test` verifies EFER.LME/LMA, kernel RIP, and VGA text in QEMU.
- **M2 — Serial + logging**
  `printf`-style formatting via COM1 (QEMU `-serial stdio`) so we can debug.
- **M3 — GDT + interrupts**
  Proper 64-bit GDT/IDT, exception handlers, PIC remap, timer (PIT) tick.
- **M4 — Keyboard input**
  PS/2 scancode decoding, a tiny input line, basic on-screen shell.
- **M5 — Memory management**
  Physical frame allocator, paging, a kernel `malloc`/`kmalloc`.
- **M6 — Userland (optional, ambitious)**
  ELF loader, ring 3, syscalls, multiple processes.

---

## Toolchain (already verified on this box)

`gcc` (freestanding) · `nasm` · `ld`/`objcopy` · `make` · `qemu-system-x86_64` · `xorriso`
