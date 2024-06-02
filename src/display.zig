const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const Mutex = @import("std").Thread.Mutex;

pub const DisplayErrors = error{ InitFailed, RenderError };

pub const Display = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,

    pixels: [64 * 32]bool,

    const Self = Display;

    pub fn init() !Self {
        const window_opt = c.SDL_CreateWindow("chip-8", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 640, 320, c.SDL_WINDOW_SHOWN);
        if (window_opt == null) {
            return DisplayErrors.InitFailed;
        }

        const window = window_opt.?;
        const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED).?;

        if (c.SDL_RenderSetScale(renderer, 10, 10) != 0) {
            return DisplayErrors.InitFailed;
        }

        return Self{
            .window = window,
            .renderer = renderer,
            .pixels = undefined,
        };
    }

    pub fn clear(self: *Self) !void {
        @memset(self.pixels[0..self.pixels.len], false);
    }

    pub fn toggle_pixel(self: *Self, x: i32, y: i32) bool {
        const pos: usize = @intCast(y * 64 + x);

        self.pixels[pos] = !self.pixels[pos];
        return !self.pixels[pos];
    }

    pub fn render(self: *Self) !void {
        var on_points: [64 * 32]c.SDL_Point = undefined;
        var on_len: usize = 0;
        var off_points: [64 * 32]c.SDL_Point = undefined;
        var off_len: usize = 0;

        for (self.pixels, 0..) |on, idx| {
            if (on) {
                on_points[on_len] = c.SDL_Point{
                    .x = @intCast(@rem(idx, 64)),
                    .y = @intCast(@divTrunc(idx, 64)),
                };
                on_len += 1;
            } else {
                off_points[off_len] = c.SDL_Point{
                    .x = @intCast(@rem(idx, 64)),
                    .y = @intCast(@divTrunc(idx, 64)),
                };
                off_len += 1;
            }
        }

        _ = c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 0xFF);

        if (c.SDL_RenderDrawPoints(self.renderer, &off_points, @intCast(off_len)) > 0) {
            return DisplayErrors.RenderError;
        }

        _ = c.SDL_SetRenderDrawColor(self.renderer, 0xFF, 0xFF, 0xFF, 0xFF);

        if (c.SDL_RenderDrawPoints(self.renderer, &on_points, @intCast(on_len)) > 0) {
            return DisplayErrors.RenderError;
        }

        c.SDL_RenderPresent(self.renderer);
    }

    pub fn deinit(self: Self) void {
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
    }
};
