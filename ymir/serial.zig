const ymir = @import("ymir");
const arch = ymir.arch;

pub const Serial = struct {
    const Self = @This();
    const WriteFn = *const fn (u8) void;
    const ReadFn = *const fn () ?u8;

    _write_fn: WriteFn = undefined,
    _read_fn: ReadFn = undefined,

    pub fn init() Serial {
        var serial = Serial{};
        arch.serial.initSerial(&serial, .com1, 115200);
        return serial;
    }

    pub fn write(self: Self, c: u8) void {
        self._write_fn(c);
    }

    pub fn writeString(self: Self, s: []const u8) void {
        for (s) |c| {
            self.write(c);
        }
    }
};
