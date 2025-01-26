const std = @import("std");
const uefi = std.os.uefi;

const Writer = std.io.Writer(
    void,
    LogError,
    writerFunction,
);
const LogError = error{};

fn writerFunction(_: void, bytes: []const u8) LogError!usize {
    const con_out = uefi.system_table.con_out orelse return .Aborted;
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
    _ = level;
    _ = scope;

    std.fmt.format(
        Writer{ .context = {} },
        fmt ++ "\r\n",
        args,
    ) catch unreachable;
}

pub const default_log_options = std.Options{
    .logFn = log,
};