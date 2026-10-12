# MOS

A tiny **x86-64 operating system** written in NASM assembly and freestanding C.
It uses its **own two-stage BIOS bootloader**, enters 64-bit long mode, and prints
colored text to VGA memory. No GRUB or libc.

## Requirements

`nasm`, `gcc`, `binutils` (`ld`, `objcopy`), `make`, `python3`, and
`qemu-system-x86_64` to run and test it. Developed on Linux.

## Build and run

```sh
make          # build/boot.bin, build/stage2.bin, build/kernel.bin, build/os.img
make run      # boot the disk image in QEMU (graphical display required)
make test     # verify long mode + VGA text in headless QEMU
make clean    # remove generated files
```

To boot the image yourself: `qemu-system-x86_64 -drive if=ide,format=raw,file=build/os.img -boot c -m 64M`.
The raw disk image is a 2 MiB BIOS-bootable image (not an ISO). If a GitHub
release is available, its `MOS.img` asset is the same bootable image.

## Source map

- `boot/boot.asm` — 512-byte BIOS boot sector; loads stage 2 with INT 13h extensions.
- `boot/stage2.asm` — loads kernel, switches through protected mode to 64-bit long mode.
- `kernel/kernel_entry.asm` — 64-bit entry at 1 MiB; calls C.
- `kernel/kernel.c`, `kernel/vga.h` — VGA text screen.
- `kernel/linker.ld` — kernel memory layout.
- `tests/smoke.py` — QEMU register and VGA-memory smoke test.
- `PLAN.md` — architecture, memory map, and next milestones.

This first milestone is intentionally small: no keyboard, interrupts, filesystem,
or user programs yet. See `PLAN.md` for the roadmap.
