const std = @import("std");
const option = @import("option"); // build.zig で指定したオプション名
const ymir = @import("ymir");

const log_level = option.log_level;

const Writer = std.io.Writer(
    void,
    LogError,
    write,
);
const LogError = error{};

pub const default_log_options = std.Options{
    .log_level = switch (option.log_level) {
        .debug => .debug,
        .info => .info,
        .warn => .warn,
        .err => .err,
    },
    .logFn = log,
};

fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime fmt: []const u8,
    args: anytype,
) void {
    const level_str = comptime switch (level) {
        .debug => "[DEBUG]",
        .info => "[INFO ]",
        .warn => "[WARN ]",
        .err => "[ERROR]",
    };

    const scope_str = if (@tagName(scope).len <= 7) b: {
        break :b std.fmt.comptimePrint("{s: <7} | ", .{@tagName(scope)});
    } else b: {
        break :b std.fmt.comptimePrint("{s: <7}-| ", .{@tagName(scope)[0..7]});
    };

    std.fmt.format(
        Writer{ .context = {} },
        level_str ++ " " ++ scope_str ++ fmt ++ "\n",
        args,
    ) catch {};
}

const Serial = ymir.serial.Serial;
var serial: Serial = undefined;

pub fn init(ser: Serial) void {
    serial = ser;
}

pub fn write(_: void, bytes: []const u8) LogError!usize {
    serial.writeString(bytes);
    return bytes.len;
}
