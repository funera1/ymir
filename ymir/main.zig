const std = @import("std");
const surtr = @import("surtr");
const log = std.log.scoped(.ymir);

const ymir = @import("ymir");
const arch = ymir.arch;
const serial = ymir.serial.Serial;
const klog = ymir.klog;
const mem = ymir.mem;

pub const panic = ymir.panic.panic_fn;

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
    arch.intr.init();
    log.info("Initialized IDT.", .{});

    // #GPを発生
    // const ptr: *u64 = @ptrFromInt(0xDEAD_0000_0000_0000);
    // log.info("ptr.* = {d}", .{ptr.*});

    // memory allocator
    mem.initPageAllocator(boot_info.memory_map);
    log.info("Initialized page allocator", .{});
    const page_allocator = ymir.mem.page_allocator;

    const array = try page_allocator.alloc(u32, 4);
    log.debug("memory allocated @ {X:0>16}", .{@intFromPtr(array.ptr)});
    page_allocator.free(array);

    log.info("Reconstrcuting memory mapping...", .{});
    try mem.reconstrctMapping(mem.page_allocator);

    while (true) asm volatile ("hlt");
}
