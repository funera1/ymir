fn writerFunction(_: void, bytes: []const u8) LogError!usize {
    for (bytes) |b| {
        con_out.outputString(&[_:0]u16{b}).err() catch unreachable;
    }
    return bytes.len;
}

fn log (
    comptime level: stdlog.Level,
    scope: @Type(.EnumLiteral),
    comptime fmt: []const u8,
    args: anytype,
) void {
    _ = level;
    _ = scope;

    const Write = std.io.Writer(
        void,
        LogError,
        writerFunction,
    );
    const LogError = error{};

    std.fmt.format(
        Writer{ .context = {} },
        fmt ++ "\r\n",
        args,
    ) catch unreachable;
}

pub const default_log_options = std.Options{
    .logFn = log,
}