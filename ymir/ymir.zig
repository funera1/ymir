pub const arch = @import("arch.zig");
pub const mem = @import("mem.zig");
pub const serial = @import("serial.zig");
pub const bits = @import("bits.zig");
pub const klog = @import("log.zig");

const testing = @import("std").testing;
test {
    testing.refAllDeclsRecursive(@This());
}

/// Halt endlessly with interrupts disabled.
pub fn endlessHalt() noreturn {
    arch.disableIntr();
    while (true) arch.halt();
}
