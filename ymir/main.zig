const std = @import("std");
const surtr = @import("surtr");
const log = std.log.scoped(.ymir);

const ymir = @import("ymir");
const arch = ymir.arch;
const serial = ymir.serial.Serial;
const klog = ymir.klog;

pub const std_options = klog.default_log_options;
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

fn validateBootInfo(boot_info: surtr.BootInfo) !void {
    if (boot_info.magic != surtr.magic) {
        return error.InvalidMagic;
    }
}

fn kernelMain(boot_info: surtr.BootInfo) !void {
    const sr = serial.init();
    klog.init(sr);
    log.info("Booting Ymir...", .{});

    // Validate the boot info.
    validateBootInfo(boot_info) catch {
        log.err("Invalid boot info", .{});
        return error.InvalidBootInfo;
    };

    // GDTの初期化
    arch.gdt.init();
    log.info("Initialized GDT.", .{});

    // IDTの初期化
    arch.idt.init();
    log.info("Initialized IDT.", .{});

    while (true) asm volatile ("hlt");
}
