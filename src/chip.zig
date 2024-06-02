const std = @import("std");
const mem = std.mem;

const dspl = @import("display.zig");
const stck = @import("stack.zig");

const print = std.debug.print;

const font = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

const program_location = 0x200;

const Errors = error{
    UnknownInstruction,
};

var RndGen = std.rand.DefaultPrng.init(0);

pub const Chip8 = struct {
    memory: [4096]u8,
    stack: stck.Stack,
    display: *dspl.Display,

    program_counter: u16,
    i: u16,

    v: [16]u8,

    delay_timer: u8,
    sound_timer: u8,

    running: bool,
    cpu_thread: std.Thread,
    timer_thread: std.Thread,

    pressed_key: u8,
    keyboard: [16]bool,

    const Self = @This();

    pub fn init(display: *dspl.Display) Self {
        var c = Chip8{
            .display = display,
            .stack = stck.Stack.init(),
            .program_counter = 0,
            .i = 0,
            .delay_timer = 0,
            .sound_timer = 0,
            .memory = undefined,
            .v = undefined,

            .running = false,
            .cpu_thread = undefined,
            .timer_thread = undefined,

            .pressed_key = 0xFF,
            .keyboard = undefined,
        };

        @memcpy(c.memory[0..80], font[0..]);

        return c;
    }

    pub fn start(self: *Self) !void {
        self.running = true;

        self.cpu_thread = try std.Thread.spawn(.{}, Self.cpu_thread, .{self});
        self.cpu_thread = try std.Thread.spawn(.{}, Self.timer_thread, .{self});
    }

    pub fn stop(self: *Self) void {
        self.running = false;

        self.cpu_thread.join();
    }

    fn cpu_thread(self: *Self) !void {
        while (true) {
            if (!self.running) {
                return;
            }

            try self.exec_op();
            std.time.sleep(1.3E6);
        }
    }

    fn timer_thread(self: *Self) !void {
        while (true) {
            if (!self.running) {
                return;
            }

            if (self.delay_timer > 0) {
                self.delay_timer -= 1;
            }
            if (self.sound_timer > 0) {
                self.sound_timer -= 1;
            }
            std.time.sleep(16E6); // around 60Hz
        }
    }

    fn set_sound_timer(self: *Self, val: u8) void {
        self.sound_timer = val;
    }

    fn set_delay_timer(self: *Self, val: u8) void {
        self.delay_timer = val;
    }

    pub fn key_change(self: *Self, key: usize, val: bool) void {
        if (val) {
            self.pressed_key = @intCast(key);
        }

        self.keyboard[key] = val;
    }

    fn exec_op(self: *Self) !void {
        const instruction: u16 = mem.readPackedInt(u16, self.memory[self.program_counter .. self.program_counter + 2], 0, std.builtin.Endian.big);

        //self.print_debug(instruction);

        self.program_counter += 2;

        switch (instruction & 0xF000) {
            0x0000 => {
                if (instruction == 0x00EE) {
                    self.program_counter = try self.stack.pop();
                } else {
                    try self.display.clear();
                }
            },
            0x1000 => {
                self.program_counter = instruction & 0x0FFF;
            },
            0x2000 => {
                try self.stack.push(self.program_counter);
                self.program_counter = instruction & 0x0FFF;
            },
            0x3000 => {
                const x: u4 = @truncate((instruction & 0x0F00) >> 8);
                const val: u8 = @truncate(instruction);
                if (self.v[x] == val) {
                    self.program_counter += 2;
                }
            },
            0x4000 => {
                const x: u4 = @truncate((instruction & 0x0F00) >> 8);
                const val: u8 = @truncate(instruction);
                if (self.v[x] != val) {
                    self.program_counter += 2;
                }
            },
            0x5000 => {
                const x: u4 = @truncate((instruction & 0x0F00) >> 8);
                const y: u4 = @truncate((instruction & 0x00F0) >> 4);
                if (self.v[x] == self.v[y]) {
                    self.program_counter += 2;
                }
            },
            0x6000 => {
                const x: u8 = @truncate((instruction & 0x0F00) >> 8);
                self.v[x] = @truncate(instruction & 0xFF);
            },
            0x7000 => {
                const x: u8 = @truncate((instruction & 0x0F00) >> 8);
                const val: u8 = @truncate(instruction & 0xFF);

                self.v[x] = self.v[x] +% val;
            },
            0x8000 => {
                switch (instruction & 0x000F) {
                    0 => {
                        const x: u4 = @truncate((instruction & 0x0F00) >> 8);
                        const y: u4 = @truncate((instruction & 0x00F0) >> 4);
                        self.v[x] = self.v[y];
                    },
                    1 => {
                        const x: u4 = @truncate((instruction & 0x0F00) >> 8);
                        const y: u4 = @truncate((instruction & 0x00F0) >> 4);
                        self.v[x] |= self.v[y];
                    },
                    2 => {
                        const x: u4 = @truncate((instruction & 0x0F00) >> 8);
                        const y: u4 = @truncate((instruction & 0x00F0) >> 4);
                        self.v[x] &= self.v[y];
                    },
                    3 => {
                        const x: u4 = @truncate((instruction & 0x0F00) >> 8);
                        const y: u4 = @truncate((instruction & 0x00F0) >> 4);
                        self.v[x] ^= self.v[y];
                    },
                    4 => {
                        const x: u4 = @truncate((instruction & 0x0F00) >> 8);
                        const y: u4 = @truncate((instruction & 0x00F0) >> 4);
                        self.v[x], self.v[0xF] = @addWithOverflow(self.v[x], self.v[y]);
                    },
                    5 => {
                        const x: u4 = @truncate((instruction & 0x0F00) >> 8);
                        const y: u4 = @truncate((instruction & 0x00F0) >> 4);
                        self.v[x], const underflow = @subWithOverflow(self.v[x], self.v[y]);
                        self.v[0xF] = if (underflow > 0) 0 else 1;
                    },
                    6 => {
                        const x: u4 = @truncate((instruction & 0x0F00) >> 8);
                        const carry = self.v[x] & 0x01;
                        self.v[x] = self.v[x] >> 1;
                        self.v[0xF] = carry;
                    },
                    7 => {
                        const x: u4 = @truncate((instruction & 0x0F00) >> 8);
                        const y: u4 = @truncate((instruction & 0x00F0) >> 4);
                        self.v[x], const underflow = @subWithOverflow(self.v[y], self.v[x]);
                        self.v[0xF] = if (underflow > 0) 0 else 1;
                    },
                    0xE => {
                        const x: u4 = @truncate((instruction & 0x0F00) >> 8);
                        const carry = (self.v[x] & 0xA0) >> 7;
                        self.v[x] = self.v[x] << 1;
                        self.v[0xF] = carry;
                    },
                    else => {
                        return Errors.UnknownInstruction;
                    },
                }
            },
            0x9000 => {
                const x: u4 = @truncate((instruction & 0x0F00) >> 8);
                const y: u4 = @truncate((instruction & 0x00F0) >> 4);
                if (self.v[x] != self.v[y]) {
                    self.program_counter += 2;
                }
            },
            0xA000 => {
                self.i = instruction & 0x0FFF;
            },
            0xC000 => {
                const x = (instruction & 0x0F00) >> 8;
                const mask: u8 = @truncate(instruction & 0xFF);

                self.v[x] = RndGen.random().int(u8) & mask;
            },
            0xD000 => {
                const vx: u8 = @truncate((instruction & 0x0F00) >> 8);
                const vy: u8 = @truncate((instruction & 0x00F0) >> 4);
                const x = @mod(self.v[vx], 64);
                const y = @mod(self.v[vy], 32);

                const n: u8 = @truncate(instruction & 0x000F);

                self.v[0xF] = 0;

                for (0..n) |row| {
                    const sprite = self.memory[self.i + row];
                    for (0..8) |col| {
                        const offset: u3 = @truncate(col);

                        const flip = sprite & (@as(u8, 1) << (7 - offset)) > 0;

                        const y_offset: i32 = @intCast(row);
                        const x_offset: i32 = @intCast(col);

                        if (x + x_offset > 63 or y + y_offset > 31) {
                            continue;
                        }

                        if (flip) {
                            if (self.display.toggle_pixel(x + x_offset, y + y_offset)) {
                                self.v[0xF] = 1;
                            }
                        }
                    }
                }
            },
            0xE000 => {
                switch (instruction & 0x00FF) {
                    0x9E => {
                        const x = (instruction & 0x0F00) >> 8;
                        if (self.keyboard[self.v[x]]) {
                            self.program_counter += 2;
                        }
                    },
                    0xA1 => {
                        const x = (instruction & 0x0F00) >> 8;
                        if (!self.keyboard[self.v[x]]) {
                            self.program_counter += 2;
                        }
                    },
                    else => return Errors.UnknownInstruction,
                }
            },
            0xF000 => {
                switch (instruction & 0x00FF) {
                    0x07 => {
                        const x = (instruction & 0xF00) >> 8;
                        self.v[x] = self.delay_timer;
                    },
                    0x0A => {
                        const x = (instruction & 0xF00) >> 8;
                        self.pressed_key = 0xFF;
                        while (self.pressed_key == 0xFF) {}
                        self.v[x] = self.pressed_key;
                    },
                    0x15 => {
                        const x = (instruction & 0xF00) >> 8;
                        self.set_delay_timer(self.v[x]);
                    },
                    0x1E => {
                        const x: u8 = @truncate((instruction & 0x0F00) >> 8);

                        self.i +%= self.v[x];
                    },
                    0x18 => {
                        const x = (instruction & 0xF00) >> 8;
                        self.set_sound_timer(self.v[x]);
                    },
                    0x29 => {
                        const x = (instruction & 0xF00) >> 8;
                        const char = self.v[x];
                        self.i = 5 * char;
                    },
                    0x33 => {
                        const x: u8 = @truncate((instruction & 0x0F00) >> 8);
                        const vx = self.v[x];

                        self.memory[self.i] = @rem(@divTrunc(vx, 100), 10);
                        self.memory[self.i + 1] = @rem(@divTrunc(vx, 10), 10);
                        self.memory[self.i + 2] = @rem(vx, 10);
                    },
                    0x55 => {
                        const x = (instruction & 0x0F00) >> 8;

                        const ptr = self.memory[self.i .. self.i + x + 1];
                        @memcpy(ptr, self.v[0 .. x + 1]);
                    },
                    0x65 => {
                        const x = (instruction & 0x0F00) >> 8;

                        const ptr = self.memory[self.i .. self.i + x + 1];
                        @memcpy(self.v[0 .. x + 1], ptr);
                    },

                    else => {
                        return Errors.UnknownInstruction;
                    },
                }
            },
            else => {
                return Errors.UnknownInstruction;
            },
        }
    }

    pub fn load_program(self: *Self, program: []const u8) void {
        const max_program_size = self.memory.len - program_location;

        mem.copyForwards(u8, self.memory[program_location..], program[0..max_program_size]);
        self.program_counter = program_location;
    }

    fn print_debug(self: Self, instr: u16) void {
        _ = self; // autofix
        print("instr: {X}\n", .{instr});
    }
};
