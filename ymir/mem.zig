pub const PageAllocator = @import("mem/PageAllocator.zig");
pub const surtr = @import("surtr");

pub const std = @import("std");
const Allocator = std.mem.Allocator;
const MemoryMap = surtr.MemoryMap;

pub var page_allocator_instance = PageAllocator.newUninit();
pub const page_allocator = Allocator{
    .ptr = &page_allocator_instance,
    .vtable = &PageAllocator.vtable,
};

pub fn initPageAllocator(map: MemoryMap) void {
    page_allocator_instance.init(map);
}
/// Physical address.
pub const Phys = u64;
/// Virtual address.
pub const Virt = u64;

pub const kib = 1024;
pub const mib = 1024 * kib;
pub const gib = 1024 * mib;

pub const page_size: u64 = page_size_4k;
pub const page_shift: u64 = page_shift_4k;
pub const page_mask: u64 = page_mask_4k;

/// Size in bytes of a 4K page.
pub const page_size_4k = 4 * kib;
/// Size in bytes of a 2M page.
pub const page_size_2mb = page_size_4k << 9;
/// Size in bytes of a 1G page.
pub const page_size_1gb = page_size_2mb << 9;
/// Shift in bits for a 4K page.
pub const page_shift_4k = 12;
/// Shift in bits for a 2M page.
pub const page_shift_2mb = 21;
/// Shift in bits for a 1G page.
pub const page_shift_1gb = 30;
/// Mask for a 4K page.
pub const page_mask_4k: u64 = page_size_4k - 1;
/// Mask for a 2M page.
pub const page_mask_2mb: u64 = page_size_2mb - 1;
/// Mask for a 1G page.
pub const page_mask_1gb: u64 = page_size_1gb - 1;
