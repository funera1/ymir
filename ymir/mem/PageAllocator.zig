const std = @import("std");
const uefi = std.os.uefi;
const Allocator = std.mem.Allocator;
const Self = @This();
const PageAllocator = Self;
const surtr = @import("surtr");
const MemoryMap = surtr.MemoryMap;
const MemoryDescriptorIterator = surtr.MemoryDescriptorIterator;

const ymir = @import("ymir");
const mem = ymir.mem;
const arch = ymir.arch;
const Phys = ymir.mem.Phys;
const Virt = ymir.mem.Virt;
const p2v = phys2virt;
const v2p = virt2phys;
const page_size = mem.page_size;
const page_mask = mem.page_mask;

const kib = mem.kib;
const mib = mem.mib;
const gib = mem.gib;

const max_physical_size = 128 * gib;
const frame_count = max_physical_size / 4096;
const MapLineType = u64;
const bits_per_mapline = @sizeOf(MapLineType) * 8;
const num_maplines = frame_count / bits_per_mapline; // 512Ki lines
const BitMap = [num_maplines]MapLineType;

// Phys-Virt変換
const FrameId = u64; // ページ番号
const bytes_per_frame = 4 * kib;

frame_begin: FrameId = 1,
frame_end: FrameId,

bitmap: BitMap = undefined,
memmap: MemoryMap = undefined,

pub const vtable = Allocator.VTable{
    .alloc = allocate,
    .free = free,
    .resize = resize,
};

// ctxはAllocator.ptrへのポインタです。Allocatorの実態は任意の構造体になり得るためanyopaqueという型になっている
fn allocate(ctx: *anyopaque, n: usize, _: u8, _: usize) ?[*]u8 {
    const self: *PageAllocator = @alignCast(@ptrCast(ctx));
    const num_frames = (n + page_size - 1) / page_size;
    var start_frame = self.frame_begin;

    // 連続したnum_frames個のページを確保できるメモリ領域を探索し、あればそのメモリ領域を確保する
    while (true) {
        var i: usize = 0;
        while (i < num_frames) : (i += 1) {
            if (start_frame + i >= self.frame_end) return null;
            if (self.get(start_frame + i) == .used) break;
        }
        if (i == num_frames) {
            self.markAllocated(start_frame, num_frames);
            return @ptrFromInt(p2v(frame2phys(start_frame)));
        }
        start_frame += i + 1;
    }
}

// freeが受け取るメモリのポインタは[]u8になっている。これはSlice型といい、ポインタとサイズを持ったfat pointerです
// このおかげで、Zigのアロケータは解放を要求されたメモリアドレスとそのサイズを紐付ける必要がない
fn free(ctx: *anyopaque, slice: []u8, _: u8, _: usize) void {
    const self: *PageAllocator = @alignCast(@ptrCast(ctx));

    const num_frames = (slice.len + page_size - 1) / page_size;
    const start_frame_vaddr: Virt = @intFromPtr(slice.ptr) & ~page_mask;
    const start_frame = phys2frame(v2p(start_frame_vaddr));
    self.markNotUsed(start_frame, num_frames);
}

fn resize(_: *anyopaque, _: []u8, _: u8, _: usize, _: usize) bool {
    @panic("unimplemented");
    // 実装: freeしてからallocateを呼ぶ
}

pub fn init(self: *Self, map: MemoryMap) void {
    var avail_end: Phys = 0;
    var desc_iter = MemoryDescriptorIterator.new(map);

    // メモリマップをひとつずつiterateし、そのメモリ領域がYmirが利用可能であればビットマップに記録する
    while (true) {
        const desc: *uefi.tables.MemoryDescriptor = desc_iter.next() orelse break;

        // Mark holes between regions as allocated (used)
        if (avail_end < desc.physical_start) {
            self.markAllocated(phys2frame(avail_end), desc.number_of_pages);
        }
        // Mark the region described by the descriptor as used or unused
        const phys_end = desc.physical_start + desc.number_of_pages * page_size;
        if (isUsableMemory(desc)) {
            avail_end = phys_end;
            self.markNotUsed(phys2frame(desc.physical_start), desc.number_of_pages);
        } else {
            self.markAllocated(phys2frame(desc.physical_start), desc.number_of_pages);
        }

        self.frame_end = phys2frame(avail_end);
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
    return Status.from(self.bitmap[line_index] & (@as(MapLineType, 1) << bit_index) != 0);
}

fn set(self: *Self, frame: FrameId, status: Status) void {
    const line_index = frame / bits_per_mapline;
    const bit_index: u6 = @truncate(frame % bits_per_mapline);
    switch (status) {
        .used => self.bitmap[line_index] |= (@as(MapLineType, 1) << bit_index),
        .unused => self.bitmap[line_index] &= ~(@as(MapLineType, 1) << bit_index),
    }
}

// 複数ページの状態をまとめて更新するヘルパー関数
fn markAllocated(self: *Self, frame: FrameId, num_frames: usize) void {
    for (0..num_frames) |i| {
        self.set(frame + i, .used);
    }
}

fn markNotUsed(self: *Self, frame: FrameId, num_frames: usize) void {
    for (0..num_frames) |i| {
        self.set(frame + i, .unused);
    }
}

pub fn allocPages(self: *PageAllocator, num_pages: usize, align_size: usize) ?[]u8 {
    const num_frames = num_pages;
    const align_frame = (align_size + page_size - 1) / page_size;
    var start_frame = align_frame;

    while (true) {
        var i: usize = 0;
        while (i < num_frames) : (i += 1) {
            if (start_frame + i >= self.frame_end) return null;
            if (self.get(start_frame + i) == .used) break;
        }
        if (i == num_frames) {
            self.markAllocated(start_frame, num_frames);
            const virt_addr: [*]u8 = @ptrFromInt(p2v(frame2phys(start_frame)));
            return virt_addr[0 .. num_pages * page_size];
        }

        start_frame += align_frame;
        if (start_frame + num_frames >= self.frame_end) return null;
    }
}

pub fn newUninit() Self {
    return Self{
        .frame_end = undefined,
        .bitmap = undefined,
    };
}
