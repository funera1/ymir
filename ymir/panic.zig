const std = @import("std");
const ymir = @import("ymir");
const arch = @import("arch.zig");
const builtin = std.builtin;
const log = std.log.scoped(.ymir);
var panicked = false;
pub const panic_fn = panic;

fn panic(msg: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    @setCold(true);
    arch.disableIntr();
    log.err("{s}", .{msg});

    if (panicked) {
        log.err("Double panic detected. Halting.", .{});
        ymir.endlessHalt();
    }
    panicked = true;

    // スタックトレースの表示
    var it = std.debug.StackIterator.init(@returnAddress(), null);
    var ix: usize = 0;
    log.err("=== Stack Trace ==============", .{});
    while (it.next()) |frame| : (ix += 1) {
        log.err("#{d:0>2}: 0x{X:0>16}", .{ ix, frame });
    }

    ymir.endlessHalt();
}

pub fn endlessHalt() noreturn {
    arch.disableIntr();
    while (true) arch.halt();
}
