const std = @import("std");
const blog = @import("log.zig");
const arch = @import("arch.zig");

pub const std_options = blog.default_log_options;
const uefi = std.os.uefi;
const elf = std.elf;
const log = std.log.scoped(.surtr);

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
    var header_buffer:  [*]align(8) u8 = undefined;
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

    while (true)
        asm volatile ("hlt");
    
    return .success;
}