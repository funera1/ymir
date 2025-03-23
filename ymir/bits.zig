const testing = @import("std").testing;

test "tobit" {
    try testing.expectEqual(0b0000_0001, tobit(u8, 0));
    try testing.expectEqual(0b0001_0000, tobit(u8, 4));
    try testing.expectEqual(0b1000_0000, tobit(u8, 7));
}

// あるNを受取、N番目のビットのみを立てた整数値を返す
pub fn tobit(T: type, nth: anytype) T {
    const val = switch (@typeInfo(@TypeOf(nth))) {
        .Int, .ComptimeInt => nth,
        .Enum => @intFromEnum(nth),
        else => @compileError("tobit: invalid type"),
    };
    return @as(T, 1) << @intCast(val);
}

// あるNとvalを受取、valのNビット目が立っているかを判定
pub inline fn isset(val: anytype, nth: anytype) bool {
    const int_nth = switch (@typeInfo(@TypeOf(nth))) {
        .Int, .ComptimeInt => nth,
        .Enum => @intFromEnum(nth),
        else => @compileError("isset: invalid type"),
    };
    return ((val >> @intCast(int_nth)) & 1) != 0;
}

// u32型のaとbを受取、それらを連結してu64型の整数を返す.
// ユースケース: WRMSR命令はEDXとEAXを連結した値をMSRに書き込む
pub inline fn concat(T: type, a: anytype, b: @TypeOf(a)) T {
    const U = @TypeOf(a);
    const width_T = @typeInfo(T).Int.bits;
    const width_U = switch (@typeInfo(U)) {
        .Int => |t| t.bits,
        .ComptimeInt => width_T / 2,
        else => @compileError("concat: invalid type"),
    };
    if (width_T != width_U * 2) @compileError("concat: invalid type");
    return (@as(T, a) << width_U) | @as(T, b);
}
