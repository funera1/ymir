const std = @import("std");
const uefi = std.os.uefi;
const Allocator = std.mem.Allocator;
const Self = @This();
const PageAllocator = Self;
const surtr = @import("surtr");
const MemoryMap = surtr.defs.MemoryMap;
const Phys = surtr.arch.Phys;
const Virt = surtr.arch.Virt;

pub const vtable = Allocator.VTable{
    .alloc = allocate,
    .free = free,
    .resize = resize,
};

fn allocate(ctx: *anyopaque, _: usize, _: u8, _: usize) ?[*]u8 {
    @panic("unimplemented");
}

fn free(ctx: *anyopaque, _: []u8, _: u8, _: usize) void {}

fn resize(ctx: *anyopaque, _: []u8, _: u8, _: usize, _: usize) bool {
    @panic("unimplemented");
}

pub fn init(self: *Self, map: MemoryMap) void {
    var avail_end: Phys = 0;
    var desc_iter = MemoryDescriptorIterator.new(map);

    while (true) {
        const desc: *uefi.tables.MemoryDescriptor = desc_iter.next() orelse break;
    }
}

inline fn isUsableMemory(descriptor: *uefi.tables.MemoryDescriptor) bool {
    return switch (descriptor.type) {
        .ConventionalMemory,
        .BootServicesCode,
        => true,
        else => false,
    };
}

const max_physical_size = 128 * gib;
const frame_count = max_physical_size / 4096;
const MapLineType = u64;
const bits_per_mapline = @sizeOf(MapLineType) * 8;
const num_maplines = frame_count / bits_per_mapline; // 512Ki lines
const BitMap = [num_maplines]MapLineType;

// Phys-Virt変換
const FrameId = u64; // ページ番号
const bytes_per_frame = 4 * kib;

inline fn phys2frame(phys: Phys) FrameId {
    return phys / bytes_per_frame;
}

inline fn frame2phys(frame: FrameId) Phys {
    return frame * bytes_per_frame;
}

// NOTE: 現在は仮想アドレスも物理アドレスもUEFIから提供されたダイレクトマップを使っているので等しい
pub fn virt2phys(addr: anytype) Phys {
    return @intCast(addr);
}

pub fn phys2virt(addr: anytype) Virt {
    return @intCast(addr);
}

const Status = enum(u1) {
    /// Page frame is in use
    used = 0,
    /// Page frame is unused
    unused = 1,

    pub inline fn from(boolean: bool) Status {
        return if (boolean) .used else .unused;
    }
};

fn get(self: *Self, frame: FrameId) Status {
    const line_index = frame / bits_per_mapline;
    const bit_index: u6 = @truncate(frame % bits_per_mapline);
    return Status.from(self.bitmap[line_index] & bits.tobit(MapLineType, bit_index) != 0);
}

fn set(self: *Self, frame: FrameId, status: Status) void {
    const line_index = frame / bits_per_mapline;
    const bit_index: u6 = @truncate(frame % bits_per_mapline);
    switch (status) {
        .used => self.bitmap[line_index] |= bits.tobit(MapLineType, bit_index),
        .unused => self.bitmap[line_index] &= ~bits.tobit(MapLineType, bit_index),
    }
}
