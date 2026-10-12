NASM := nasm
CC := gcc
LD := ld
OBJCOPY := objcopy
QEMU := qemu-system-x86_64

CFLAGS := -std=c11 -O2 -Wall -Wextra -Werror -ffreestanding -fno-pie -fno-pic \
          -fno-stack-protector -fno-builtin -fno-asynchronous-unwind-tables \
          -fno-unwind-tables -m64 -mno-red-zone -mno-sse -mno-sse2

.PHONY: all run test clean
all: build/os.img

build:
	mkdir -p build

build/boot.bin: boot/boot.asm | build
	$(NASM) -f bin $< -o $@
	@test "$$(stat -c%s $@)" -eq 512 || { echo "Boot sector is not 512 bytes"; exit 1; }

build/kernel.o: kernel/kernel.c kernel/vga.h | build
	$(CC) $(CFLAGS) -c $< -o $@

build/entry.o: kernel/kernel_entry.asm | build
	$(NASM) -f elf64 $< -o $@

build/kernel.elf: build/kernel.o build/entry.o kernel/linker.ld
	$(LD) -m elf_x86_64 --build-id=none -nostdlib -T kernel/linker.ld build/entry.o build/kernel.o -o $@

build/kernel.bin: build/kernel.elf
	$(OBJCOPY) -O binary $< $@
	@test "$$(stat -c%s $@)" -le 65024 || { echo "Kernel exceeds 127-sector BIOS read buffer"; exit 1; }

build/stage2.bin: boot/stage2.asm build/kernel.bin | build
	@size=$$(stat -c%s build/kernel.bin); sectors=$$(( (size + 511) / 512 )); \
	  $(NASM) -f bin -DKERNEL_SECTORS=$$sectors $< -o $@
	@test "$$(stat -c%s $@)" -eq 4096 || { echo "Stage 2 must be 8 sectors"; exit 1; }

build/os.img: build/boot.bin build/stage2.bin build/kernel.bin
	cat build/boot.bin build/stage2.bin build/kernel.bin > $@
	truncate -s 2M $@
	@echo "Built $@ ($$(stat -c%s build/kernel.bin)-byte kernel at LBA 9)"

run: build/os.img
	$(QEMU) -drive if=ide,format=raw,file=build/os.img -boot c -m 64M

test: build/os.img
	python3 tests/smoke.py

clean:
	rm -rf build
