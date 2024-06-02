# Chip8 Emulator

This is my first implementation of the [CHIP-8](https://en.wikipedia.org/wiki/CHIP-8).
I used this project to try out and learn [⚡ Zig](https://ziglang.org/).

The emulator passes the Corax+ opcode and flags tests from https://github.com/Timendus/chip8-test-suite.
SDL2 library is used to create the display.

Sound is not implemented.

## Usage

```bash
zig build run -- <path-to-chip8-program>
```
