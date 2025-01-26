const std = @import("std");
const option = @import("option"); // build.zig で指定したオプション名
const log_level = option.log_level;
const uefi = std.os.uefi;

const Writer = std.io.Writer(
    void,
    LogError,
    writerFunction,
);
const LogError = error{};

const Sto = uefi.protocol.SimpleTextOutput;
var con_out: *Sto = undefined;

/// Initialize bootloader log.
pub fn init(out: *Sto) void {
    con_out = out;
}

fn writerFunction(_: void, bytes: []const u8) LogError!usize {
    // const con_out = uefi.system_table.con_out orelse return .Aborted;
    for (bytes) |b| {
        con_out.outputString(&[_:0]u16{b}).err() catch unreachable;
    }
    return bytes.len;
}

fn log (
    comptime level: std.log.Level,
    scope: @Type(.EnumLiteral),
    comptime fmt: []const u8,
    args: anytype,
) void {
    // _ = level;
    const level_str = comptime switch (level) {
        .debug => "[DEBUG]",
        .info  => "[INFO ]",
        .warn  => "[WARN ]",
        .err   => "[ERROR]",
    };
    const scope_str = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    std.fmt.format(
        Writer{ .context = {} },
        level_str ++ scope_str ++ fmt ++ "\r\n",
        args,
    ) catch unreachable;
}

pub const default_log_options = std.Options{
    .log_level = switch (option.log_level) {
        .debug => .debug,
        .info => .info,
        .warn => .warn,
        .err => .err,
    },
    .logFn = log,
};