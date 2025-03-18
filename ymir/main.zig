const std = @import("std");

const ymir = @import("ymir");
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
    while (true) asm volatile ("hlt");
}
