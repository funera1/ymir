const std = @import("std");
const blog = @import("log.zig");
const arch = @import("arch.zig");
const defs = @import("defs.zig");

pub const std_options = blog.default_log_options;
const uefi = std.os.uefi;
const elf = std.elf;
const log = std.log.scoped(.surtr);

const page_size = arch.page.page_size_4k;

// ファイルのオープン
inline fn toUcs2(comptime s: [:0]const u8) [s.len * 2:0]u16 {
    var ucs2: [s.len * 2:0]u16 = [_:0]u16{0} ** (s.len * 2);
    for (s, 0..) |c, i| {
        ucs2[i] = c;
        ucs2[i + 1] = 0;
    }
    return ucs2;
}

fn openFile(
    root: *uefi.protocol.File,
    comptime name: [:0]const u8,
) !*uefi.protocol.File {
    var file: *uefi.protocol.File = undefined;
    const status = root.open(
        &file,
        &toUcs2(name),
        uefi.protocol.File.efi_file_mode_read,
        0, // 適当に0を指定
    );

    if (status != .Success) {
        log.err("Failed to open file: {s}", .{name});
        return error.Aborted;
    }
    return file;
}

pub fn main() uefi.Status {
    var status: uefi.Status = undefined;
    const con_out = uefi.system_table.con_out orelse return .Aborted;
    status = con_out.clearScreen();

    // init log
    blog.init(con_out);
    log.info("Initialized bootloader log.", .{});

    // Surtrからファイルシステム上のファイルアクセスするためのポインタ(BootServices)
    const boot_service: *uefi.tables.BootServices = uefi.system_table.boot_services orelse {
        log.err("Failed to get boot services.", .{});
        return .Aborted;
    };
    log.info("Got boot services.", .{});

    // BootServicesからSimple FIle System Protocolを取得
    var fs: *uefi.protocol.SimpleFileSystem = undefined;
    status = boot_service.locateProtocol(&uefi.protocol.SimpleFileSystem.guid, null, @ptrCast(&fs));
    if (status != .Success) {
        log.err("Failed to locate simple file system protocol.", .{});
        return status;
    }
    log.info("Located simple file system protocol.", .{});

    // Simple File System Protocolを利用してFSのルートディレクトリを開く
    var root_dir: *uefi.protocol.File = undefined;
    status = fs.openVolume(&root_dir);
    if (status != .Success) {
        log.err("Failed to open volume.", .{});
        return status;
    }
    log.info("Opened filesytem volume.", .{});

    // ファイル open
    const kernel = openFile(root_dir, "ymir.elf") catch return .Aborted;
    log.info("Opened kernel file.", .{});

    // ファイル read
    var header_size: usize = @sizeOf(elf.Elf64_Ehdr);
    var header_buffer: [*]align(8) u8 = undefined;
    status = boot_service.allocatePool(.LoaderData, header_size, &header_buffer); // loerderDataはUEFIアプリのデータ用メモリ
    if (status != .Success) {
        log.err("Failed to allocate memory for kernel ELF header.", .{});
        return status;
    }

    status = kernel.read(&header_size, header_buffer);
    if (status != .Success) {
        log.err("Failed to read kernel ELF header.", .{});
        return status;
    }

    // ELFヘッダのパース
    const elf_header = elf.Header.parse(header_buffer[0..@sizeOf(elf.Elf64_Ehdr)]) catch |err| {
        log.err("Failed to parse kernel ELF header: {?}", .{err});
        return .Aborted;
    };
    log.info("Parsed kernel ELF header.", .{});

    log.debug(
        \\ Kernel ELF information:
        \\  Entry Point          : 0x{X}
        \\  Is 64-bit            : {d}
        \\  # of Program Headers : {d}
        \\  # of Section Headers : {d}
    ,
        .{
            elf_header.entry,
            @intFromBool(elf_header.is_64),
            elf_header.phnum,
            elf_header.shnum,
        },
    );

    arch.page.setLv4Writable(boot_service) catch |err| {
        log.err("Failed to set page table writable: {?}", .{err});
        return .LoadError;
    };
    log.debug("Set page table writable.", .{});

    arch.page.map4kTo(
        0xFFFF_FFFF_DEAD_0000,
        0x10_0000,
        .read_write,
        boot_service,
    ) catch |err| {
        log.err("Failed to map 4KiB page: {?}", .{err});
        return .Aborted;
    };

    // for ("Hello, world!\n") |b| {
    //     con_out.outputString(&[_:0]u16{ b }).err() catch unreachable;
    // }

    // カーネル用のメモリの確保
    const Addr = elf.Elf64_Addr;
    var kernel_start_virt: Addr = std.math.maxInt(Addr);
    var kernel_start_phys: Addr align(page_size) = std.math.maxInt(Addr);
    var kernel_end_phys: Addr = 0;

    var iter = elf_header.program_header_iterator(kernel);
    // PT_LOADセグメントの最小・最大アドレスを記録
    while (true) {
        const phdr = iter.next() catch |err| {
            log.err("Failed to get program header: {?}\n", .{err});
            return .LoadError;
        } orelse break;
        if (phdr.p_type != elf.PT_LOAD) continue;
        if (phdr.p_paddr < kernel_start_phys) kernel_start_phys = phdr.p_paddr;
        if (phdr.p_vaddr < kernel_start_virt) kernel_start_virt = phdr.p_vaddr;
        if (phdr.p_paddr + phdr.p_memsz > kernel_end_phys) kernel_end_phys = phdr.p_paddr + phdr.p_memsz;
    }

    // 計算したページ分メモリを確保する
    const pages_4kib = (kernel_end_phys - kernel_start_phys + (page_size - 1)) / page_size;
    status = boot_service.allocatePages(.AllocateAddress, .LoaderData, pages_4kib, @ptrCast(&kernel_start_phys));
    if (status != .Success) {
        log.err("Failed to allocate memory for kernel image: {?}", .{status});
        return status;
    }
    log.info("Kernel image: 0x{X:0>16} - 0x{X:0>16} (0x{X} pages)", .{ kernel_start_phys, kernel_end_phys, pages_4kib });

    // カーネルイメージのための仮想アドレスのマップ
    for (0..pages_4kib) |i| {
        arch.page.map4kTo(
            kernel_start_virt + page_size * i,
            kernel_start_phys + page_size * i,
            .read_write,
            boot_service,
        ) catch |err| {
            log.err("Failed to map memory for kernel image: {?}", .{err});
            return .LoadError;
        };
    }
    log.info("Mapped memory for kernel image.", .{});

    // セグメントの読み込み
    log.info("Load kernel image...", .{});
    iter = elf_header.program_header_iterator(kernel);
    while (true) {
        // ELFのセグメントをパース. ただしPT_LOAD以外はいらない
        const phdr = iter.next() catch |err| {
            log.err("Failed to get program header: {?}\n", .{err});
            return .LoadError;
        } orelse break;
        if (phdr.p_type != elf.PT_LOAD) continue;

        // setPositionでセグメントの開始オフセットまでシーク
        status = kernel.setPosition(phdr.p_offset);
        if (status != .Success) {
            log.err("Failed to set position for kernel image.", .{});
            return status;
        }

        // セグメントヘッダが要求する仮想アドレスに対して、セグメントをファイルから読み出す
        const segment: [*]u8 = @ptrFromInt(phdr.p_vaddr);
        var mem_size = phdr.p_memsz;
        status = kernel.read(&mem_size, segment);
        if (status != .Success) {
            log.err("Failed to read kernel image.", .{});
            return status;
        }
        log.info(
            "   Seg @ 0x{X:0>16} - 0x{X:0>16}",
            .{ phdr.p_vaddr, phdr.p_vaddr + phdr.p_memsz },
        );

        // bssセクションの初期化
        // .bssセクションは初期化されていないため、ファイルには記録されず、ロード時にゼロクリアされる。
        // そのため、p_filesz < p_memszになる. つまりzero_count > 0のとき、bssセクションということ
        const zero_count = phdr.p_memsz - phdr.p_filesz;
        if (zero_count > 0) {
            boot_service.setMem(@ptrFromInt(phdr.p_vaddr + phdr.p_filesz), zero_count, 0);
        }
    }

    // ELFヘッダパースのために使ったファイルのclose/メモリの開放
    status = boot_service.freePool(header_buffer);
    if (status != .Success) {
        log.err("Failed to free memory for kernel ELF header.", .{});
        return status;
    }
    status = kernel.close();
    if (status != .Success) {
        log.err("Failed to close kernel file.", .{});
        return status;
    }
    status = root_dir.close();
    if (status != .Success) {
        log.err("Failed to close filesystem volume.", .{});
        return status;
    }

    // メモリマップの取得と表示
    const map_buffer_size = page_size * 4;
    var map_buffer: [map_buffer_size]u8 = undefined;
    var map = defs.MemoryMap{
        .buffer_size = map_buffer.len,
        .descriptors = @alignCast(@ptrCast(&map_buffer)),
        .map_key = 0,
        .map_size = map_buffer.len,
        .descriptor_size = 0,
        .descriptor_version = 0,
    };
    status = getMemoryMap(&map, boot_service);

    var map_iter = defs.MemoryDescriptorIterator.new(map);
    while (true) {
        if (map_iter.next()) |md| {
            log.debug(" 0x{X:0>16} - 0x{X:0>16} : {s}", .{
                md.physical_start,
                md.physical_start + md.number_of_pages * page_size,
                @tagName(md.type),
            });
        } else break;
    }

    // boot_serviceのexit
    log.info("Exiting boot services.", .{});
    status = boot_service.exitBootServices(uefi.handle, map.map_key);
    // メモリマップはAllocatePages()やAllocatePool()によって変更された場合、エラーが出るので、再度メモリマップを取得する
    if (status != .Success) {
        map.buffer_size = map_buffer.len;
        map.map_size = map_buffer.len;
        status = getMemoryMap(&map, boot_service);
        if (status != .Success) {
            log.err("Failed to get memory map after failed to exit boot services.", .{});
            return status;
        }
        status = boot_service.exitBootServices(uefi.handle, map.map_key);
        if (status != .Success) {
            log.err("Failed to exit boot services.", .{});
            return status;
        }
    }
    // NOTE: exitしたので, これ以降boot serviceを利用できない. = log出力できなくなる

    // SurtrからYmir渡す引数
    const boot_info = defs.BootInfo{
        .magic = defs.magic,
        .memory_map = map,
    };

    // Ymirへジャンプ
    // jumpKernel(boot_info, elf_header);
    // unreachable;
    const KernelEntryType = fn (defs.BootInfo) callconv(.Win64) noreturn;
    const kernel_entry: *KernelEntryType = @ptrFromInt(elf_header.entry);
    kernel_entry(boot_info);
    unreachable;

    // while (true)
    //     asm volatile ("hlt");

    // return .success;
}

fn getMemoryMap(map: *defs.MemoryMap, boot_services: *uefi.tables.BootServices) uefi.Status {
    return boot_services.getMemoryMap(
        &map.map_size,
        map.descriptors,
        &map.map_key,
        &map.descriptor_size,
        &map.descriptor_version,
    );
}

fn jumpKernel(boot_info: defs.BootInfo, elf_header: elf.Header) void {
    const KernelEntryType = fn (defs.BootInfo) callconv(.Win64) noreturn;
    const kernel_entry: *KernelEntryType = @ptrFromInt(elf_header.entry);
    kernel_entry(boot_info);
}
