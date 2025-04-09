// `/arch`以外から使いたいモジュール
pub const serial = @import("serial.zig");
pub const gdt = @import("gdt.zig");
pub const intr = @import("interrupt.zig");
pub const idt = @import("idt.zig");

// `/arch`以外に露出したくないモジュール
const am = @import("asm.zig");

/// Pause a CPU for a short period of time.
pub fn relax() void {
    am.relax();
}

/// Disable interrupts.
/// Note that exceptions and NMI are not ignored.
pub inline fn disableIntr() void {
    am.cli();
}

/// Enable interrupts.
pub inline fn enableIntr() void {
    am.sti();
}

/// Halt the current CPU.
pub inline fn halt() void {
    am.hlt();
}

/// Pause the CPU for a wait loop.
pub inline fn pause() void {
    asm volatile ("pause");
}
