// `/arch`以外から使いたいモジュール
pub const serial = @import("serial.zig");
pub const gdt = @import("gdt.zig");

// `/arch`以外に露出したくないモジュール
const am = @import("asm.zig");
