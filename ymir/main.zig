const std = @import("std");

const ymir = @import("ymir");
const arch = ymir.arch;
const surtr = @import("surtr");

extern const __stackguard_lower: [*]const u8;

export fn kernelEntry() callconv(.Naked) noreturn {
    asm volatile (
        \\movq %[new_stack], %%rsp
        \\call kernelTrampoline
        :
        : [new_stack] "r" (@intFromPtr(&__stackguard_lower) - 0x10),
    );
}

// UEFIが用意したスタックからカーネルのスタックへ切り替えるためのトランポリン
export fn kernelTrampoline(boot_info: surtr.BootInfo) callconv(.Win64) noreturn {
    // kernelMain(boot_info) catch |err| {
    kernelMain(boot_info) catch {
        @panic("Exiting...");
    };

    unreachable;
}

fn kernelMain(_: surtr.BootInfo) !void {
    arch.serial.initSerial(.com1, 115200);
    for ("Hello, Ymir!\n") |c|
        arch.serial.writeByte(c, .com1);

    while (true) asm volatile ("hlt");
}
