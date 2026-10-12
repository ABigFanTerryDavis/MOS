#!/usr/bin/env python3
"""Boot MOS in QEMU, verify 64-bit long mode and bytes in VGA text RAM."""
import re
import shutil
import socket
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IMAGE = ROOT / "build/os.img"


def receive_prompt(conn):
    result = b""
    while not result.endswith(b"(qemu) "):
        data = conn.recv(8192)
        if not data:
            raise RuntimeError("QEMU monitor disconnected")
        result += data
    return result.decode("ascii", "replace")


def command(conn, text):
    conn.sendall((text + "\n").encode())
    return receive_prompt(conn)


def main():
    with tempfile.TemporaryDirectory(prefix="mos-test-") as temp:
        monitor = str(Path(temp) / "monitor.sock")
        # A running graphical QEMU may hold an exclusive lock on the build image.
        # Boot a throwaway copy so tests can run while the live demo stays open.
        test_image = Path(temp) / "MOS.img"
        shutil.copyfile(IMAGE, test_image)
        args = ["qemu-system-x86_64", "-accel", "tcg", "-m", "64M",
                "-drive", f"if=ide,format=raw,file={test_image}", "-boot", "c",
                "-display", "none", "-no-reboot", "-no-shutdown",
                "-monitor", f"unix:{monitor},server=on,wait=off"]
        process = subprocess.Popen(args, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 10
            with socket.socket(socket.AF_UNIX) as conn:
                conn.settimeout(5)
                while True:
                    try:
                        conn.connect(monitor)
                        break
                    except (FileNotFoundError, ConnectionRefusedError):
                        if process.poll() is not None:
                            raise RuntimeError(f"QEMU exited: {process.stderr.read().decode()}")
                        if time.monotonic() > deadline:
                            raise TimeoutError("QEMU monitor did not start")
                        time.sleep(0.05)
                receive_prompt(conn)
                while time.monotonic() < deadline:
                    regs = command(conn, "info registers")
                    if re.search(r"RIP=000000000010[0-9A-Fa-f]{4}", regs):
                        break
                    time.sleep(0.1)
                else:
                    raise AssertionError("Kernel never reached its 64-bit entry")

                efer = re.search(r"EFER=([0-9A-Fa-f]+)", regs)
                assert efer, f"EFER missing from register dump:\n{regs}"
                assert int(efer.group(1), 16) & 0x500 == 0x500, "LME/LMA not enabled"

                vga = command(conn, "xp /3hx 0xb8006")
                for word in ("0x3f4d", "0x3f4f", "0x3f53"):
                    assert word in vga.lower(), f"Expected colored 'MOS' in VGA RAM:\n{vga}"

                screenshot = ROOT / "build/screen.ppm"
                command(conn, f"screendump {screenshot}")
                assert screenshot.exists() and screenshot.stat().st_size > 10000
                print("PASS: 64-bit RIP at kernel, EFER.LME+LMA active")
                print("PASS: VGA RAM contains 'MOS' in cyan-bar color")
                print(f"Screenshot: {screenshot}")
                conn.sendall(b"quit\n")  # QEMU exits without another monitor prompt
        finally:
            if process.poll() is None:
                process.terminate()
            try:
                process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()


if __name__ == "__main__":
    main()
