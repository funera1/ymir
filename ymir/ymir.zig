pub const arch = @import("arch.zig");
pub const mem = @import("mem.zig");
pub const serial = @import("serial.zig");
pub const bits = @import("bits.zig");
pub const panic = @import("panic.zig");
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

/// Base virtual address of direct mapping.
/// The virtual address starting from the address is directly mapped to the physical address at 0x0.
pub const direct_map_base = 0xFFFF_8880_0000_0000;
/// Size in bytes of the direct mapping region.
pub const direct_map_size = 512 * mem.gib;
/// The base virtual address of the kernel.
/// The virtual address starting from the address is directly mapped to the physical address at 0x0.
pub const kernel_base = 0xFFFF_FFFF_8000_0000;
