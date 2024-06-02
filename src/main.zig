const std = @import("std");
const dspl = @import("display.zig");
const chip = @import("chip.zig");

const print = std.debug.print;

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub fn main() u8 {
    var args = std.process.args();
    _ = args.skip();

    const program_file = if (args.next()) |arg| arg else {
        print("Missing program file. Provide the path to the chip8 program as the first argument.\n", .{});
        return 1;
    };

    var program: [4096]u8 = undefined;
    _ = std.fs.cwd().readFile(program_file, program[0..]) catch {
        print("failed to read program from {s}\n", .{program_file});
        return 1;
    };

    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        print("failed to initialize SDL\n", .{});
        return 1;
    }
    defer c.SDL_Quit();

    var display = dspl.Display.init() catch {
        print("failed to init display\n", .{});
        return 1;
    };
    defer display.deinit();

    var chip8 = chip.Chip8.init(&display);
    chip8.load_program(program[0..]);
    chip8.start() catch {
        print("failed to start chip8\n", .{});
        return 1;
    };

    while (true) {
        display.render() catch |err| {
            print("failed to render display: {any}\n", .{err});
            return 1;
        };

        var ev: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&ev) == 1) {
            switch (ev.type) {
                c.SDL_QUIT => {
                    return 0;
                },
                c.SDL_KEYDOWN => {
                    chip8.key_change(map_keys(ev.key.keysym.scancode), true);
                },
                c.SDL_KEYUP => {
                    chip8.key_change(map_keys(ev.key.keysym.scancode), false);
                },
                else => {},
            }
        }

        c.SDL_Delay(16);
    }

    return 0;
}

fn map_keys(scancode: u32) usize {
    return switch (scancode) {
        30 => 1,
        31 => 2,
        32 => 3,
        33 => 0xC,
        20 => 4,
        26 => 5,
        8 => 6,
        21 => 0xD,
        4 => 7,
        22 => 8,
        7 => 9,
        9 => 0xE,
        29 => 0xA,
        27 => 0,
        6 => 0xB,
        25 => 0xF,
        else => 0,
    };
}
