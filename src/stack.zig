const StackErrors = error{ Overflow, Empty };

pub const Stack = struct {
    arr: [16]u16,
    head: usize,

    const Self = @This();

    pub fn init() Self {
        return Stack{
            .arr = undefined,
            .head = 0,
        };
    }

    pub fn push(self: *Self, val: u16) StackErrors!void {
        if (self.head >= self.arr.len) {
            return StackErrors.Overflow;
        }

        self.arr[self.head] = val;
        self.head += 1;
    }

    pub fn pop(self: *Self) StackErrors!u16 {
        if (self.head <= 0) {
            return StackErrors.Empty;
        }

        self.head -= 1;
        const val = self.arr[self.head];
        return val;
    }
};
