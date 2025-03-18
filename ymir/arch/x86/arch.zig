// `/arch`以外から使いたいモジュール
pub const serial = @import("serial.zig");
// `/arch`以外に露出したくないモジュール
const am = @import("asm.zig");
