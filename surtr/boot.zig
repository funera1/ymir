const std = @import("std");
const uefi = std.os.uefi;

pub fn main() uefi.Status {
    var status: uefi.Status = undefined

    const con_out = uefi.system_table.con_out orelse return .Aborted;
    status = con_out.clearScreen();

    for ("Hello, world!\n") |b| {
        con_out.outputString(&[_:0]u16{ b }).err() catch unreachable;
    }

    // while (true)
    //     asm volatile ("hlt");
    
    return .success;
}