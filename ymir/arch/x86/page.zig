const std = @import("std");
const ymir = @import("ymir");
const am = @import("asm.zig");
const mem = ymir.mem;
const Phys = mem.Phys;
const Virt = mem.Virt;
const Allocator = std.mem.Allocator;
const virt2phys = mem.virt2phys;
const phys2virt = mem.phys2virt;

const direct_map_base = ymir.direct_map_base;
const direct_map_size = ymir.direct_map_size;

/// Number of entries in a page table.
const num_table_entries: usize = 512;
/// Shift in bits to extract the level-4 index from a virtual address.
const lv4_shift = 39;
/// Shift in bits to extract the level-3 index from a virtual address.
const lv3_shift = 30;
/// Shift in bits to extract the level-2 index from a virtual address.
const lv2_shift = 21;
/// Shift in bits to extract the level-1 index from a virtual address.
const lv1_shift = 12;
/// Mask to extract page entry index from a shifted virtual address.
const index_mask = 0x1FF;

const page_size_4k = mem.page_size_4k;
const page_size_2mb = mem.page_size_2mb;
const page_size_1gb = mem.page_size_1gb;
const page_size_512gb = page_size_1gb * 512;
const page_shift_4k = mem.page_shift_4k;
const page_shift_2mb = mem.page_shift_2mb;
const page_shift_1gb = mem.page_shift_1gb;
const page_mask_4k = mem.page_mask_4k;
const page_mask_2mb = mem.page_mask_2mb;
const page_mask_1gb = mem.page_mask_1gb;

pub const PageError = error{
    /// Failed to allocate memory.
    OutOfMemory,
    /// Invalid address.
    InvalidAddress,
    /// Specified address is not mapped.
    NotMapped,
};

const TableLevel = enum { lv4, lv3, lv2, lv1 };
fn EntryBase(table_level: TableLevel) type {
    return packed struct(u64) {
        const Self = @This();
        const level = table_level;
        const LowerType = switch (level) {
            .lv4 => Lv3Entry,
            .lv3 => Lv2Entry,
            .lv2 => Lv1Entry,
            .lv1 => struct {},
        };

        /// Present.
        present: bool = true,
        /// Read/Write
        /// false: read-only, true: read and write
        rw: bool,
        /// User/Supervisor
        /// false: user-only, true: user/supervisor
        us: bool,
        /// Page-level write-through
        /// Indirectly determines the memory type used to access the page or page table.
        pwt: bool = false,
        /// Page-level cache disble
        pcd: bool = false,
        /// Accessed
        /// Indicates whether this entry has been used for translation
        accessed: bool = false,
        /// Dirty bit.
        dirty: bool = false,
        /// Page size.
        /// false: the entry references a page table, true: the entry maps a page
        ps: bool,
        /// Ignored when CR4.PGE != 1.
        /// Ignored when this entry references a page table.
        /// Ignored for level-4 entries.
        global: bool = true,
        /// Ignored
        _ignored1: u2 = 0,
        /// Ignored except for HLAT paging
        restart: bool = false,
        /// When the entry maps a page, physical address of the page.
        /// When the entry refereences a page table, 4KB aligned address of the page table.
        phys: u51,
        /// Execute Disable
        xd: bool = false,

        // 自身のphysをシフトして物理アドレスに変換するヘルパー関数
        pub inline fn address(self: Self) Phys {
            return @as(u64, @intCast(self.phys)) << 12;
        }

        // ページテーブルエントリを作成する関数
        pub fn newMapPage(phys: Phys, present: bool) Self {
            // Surtr/Ymirでは512GiBページはサポートしないので、Lv4Entryに対してこの関数を呼ぶ場合はコンパイラエラーとする
            if (level == .lv4) @compileError("Lv4 entry cannot map a page");
            return Self{
                .present = present,
                .rw = true,
                .us = false,
                // ページをマップするため、.ps = true
                .ps = true,
                .phys = @truncate(phys >> 12),
            };
        }

        // ページエントリを参照するエントリを作成する関数
        pub fn newMapTable(table: [*]LowerType, present: bool) Self {
            if (level == .lv1) @compileError("Lv1 entry cannot reference a page table");
            return Self{
                .present = present,
                .rw = true,
                .us = false,
                .ps = false,
                .phys = @truncate(@intFromPtr(table) >> 12),
            };
        }
    };
}

const Lv4Entry = EntryBase(.lv4);
const Lv3Entry = EntryBase(.lv3);
const Lv2Entry = EntryBase(.lv2);
const Lv1Entry = EntryBase(.lv1);

fn getTable(T: type, addr: Phys) []T {
    const ptr: [*]T = @ptrFromInt(addr & ~page_mask_4k);
    return ptr[0..num_table_entries];
}
fn getLv4Table(cr3: Phys) []Lv4Entry {
    return getTable(Lv4Entry, cr3);
}
fn getLv3Table(lv3_paddr: Phys) []Lv3Entry {
    return getTable(Lv3Entry, lv3_paddr);
}
fn getLv2Table(lv2_paddr: Phys) []Lv2Entry {
    return getTable(Lv2Entry, lv2_paddr);
}
fn getLv1Table(lv1_paddr: Phys) []Lv1Entry {
    return getTable(Lv1Entry, lv1_paddr);
}

fn getEntry(T: type, vaddr: Virt, paddr: Phys) *T {
    const table = getTable(T, paddr);
    const shift = switch (T) {
        Lv4Entry => 39,
        Lv3Entry => 30,
        Lv2Entry => 21,
        Lv1Entry => 12,
        else => @compileError("Unsupported type"),
    };
    // 9bit-mask. Tableの先頭からindex番目のEntryを返す
    return &table[(vaddr >> shift) & 0x1FF];
}

fn getLv4Entry(addr: Virt, cr3: Phys) *Lv4Entry {
    return getEntry(Lv4Entry, addr, cr3);
}
fn getLv3Entry(addr: Virt, lv3tbl_paddr: Phys) *Lv3Entry {
    return getEntry(Lv3Entry, addr, lv3tbl_paddr);
}
fn getLv2Entry(addr: Virt, lv2tbl_paddr: Phys) *Lv2Entry {
    return getEntry(Lv2Entry, addr, lv2tbl_paddr);
}
fn getLv1Entry(addr: Virt, lv1tbl_paddr: Phys) *Lv1Entry {
    return getEntry(Lv1Entry, addr, lv1tbl_paddr);
}

fn allocatePage(allocator: Allocator) PageError![*]align(page_size_4k) u8 {
    return (allocator.alignedAlloc(
        u8,
        page_size_4k,
        page_size_4k,
    ) catch return PageError.OutOfMemory).ptr;
}

pub fn reconstruct(allocator: Allocator) PageError!void {
    const lv4tbl_ptr: [*]Lv4Entry = @ptrCast(try allocatePage(allocator));
    const lv4tbl = lv4tbl_ptr[0..num_table_entries]; // 512
    @memset(lv4tbl, std.mem.zeroes(Lv4Entry));

    const lv4idx_start = (direct_map_base >> lv4_shift) & index_mask;
    const lv4idx_end = lv4idx_start + (direct_map_size >> lv4_shift);

    // Create the direct mapping using 1GiB pages
    for (lv4tbl[lv4idx_start..lv4idx_end], 0..) |*lv4ent, i| {
        const lv3tbl: [*]Lv3Entry = @ptrCast(try allocatePage(allocator));
        for (0..num_table_entries) |lv3idx| {
            lv3tbl[lv3idx] = Lv3Entry.newMapPage(
                (i << lv4_shift) + (lv3idx << lv3_shift),
                true,
            );
        }
        lv4ent.* = Lv4Entry.newMapTable(lv3tbl, true);
    }

    // UEFIが提供するページテーブルからDirect Map Regionよりも高位にマップされている領域をクローンする
    // この領域を使っているのはカーネルイメージだけ

    // Recursively clone tables for the kernel region.
    const old_lv4tbl = getLv4Table(am.readCr3()); // Lv4テーブルのアドレスはCR3の値から取得できる
    for (lv4idx_end..num_table_entries) |lv4idx| {
        if (old_lv4tbl[lv4idx].present) {
            const lv3tbl = getLv3Table(old_lv4tbl[lv4idx].address());
            const new_lv3tbl = try cloneLevel3Table(lv3tbl, allocator);
            lv4tbl[lv4idx] = Lv4Entry.newMapTable(new_lv3tbl.ptr, true);
        }
    }

    const cr3 = @intFromPtr(lv4tbl) & ~@as(u64, 0xFFF);
    am.loadCr3(cr3);
    // CR3へ書き込みを行うと、TLBの前エントリがフラッシュされ古いエントリが無効になる
}

// LV3以下のテーブルもreconstructと同様にクローンしていく
fn cloneLevel3Table(lv3_table: []Lv3Entry, allocator: Allocator) PageError![]Lv3Entry {
    const new_lv3ptr: [*]Lv3Entry = @ptrCast(try allocatePage(allocator));
    const new_lv3tbl = new_lv3ptr[0..num_table_entries];
    @memcpy(new_lv3tbl, lv3_table);

    for (new_lv3tbl) |*lv3ent| {
        if (!lv3ent.present) continue;
        if (lv3ent.ps) continue;

        const lv2tbl = getLv2Table(lv3ent.address());
        const new_lv2tbl = try cloneLevel2Table(lv2tbl, allocator);
        lv3ent.phys = @truncate(virt2phys(@intFromPtr(new_lv2tbl.ptr)) >> page_shift_4k);
    }

    return new_lv3tbl;
}

fn cloneLevel2Table(lv2_table: []Lv2Entry, allocator: Allocator) PageError![]Lv2Entry {
    const new_lv2ptr: [*]Lv2Entry = @ptrCast(try allocatePage(allocator));
    const new_lv2tbl = new_lv2ptr[0..num_table_entries];
    @memcpy(new_lv2tbl, lv2_table);

    for (new_lv2tbl) |*lv2ent| {
        if (!lv2ent.present) continue;
        if (lv2ent.ps) continue;

        const lv1tbl = getLv1Table(lv2ent.address());
        const new_lv1tbl = try cloneLevel1Table(lv1tbl, allocator);
        lv2ent.phys = @truncate(virt2phys(@intFromPtr(new_lv1tbl.ptr)) >> page_shift_4k);
    }

    return new_lv2tbl;
}

fn cloneLevel1Table(lv1_table: []Lv1Entry, allocator: Allocator) PageError![]Lv1Entry {
    const new_lv1ptr: [*]Lv1Entry = @ptrCast(try allocatePage(allocator));
    const new_lv1tbl = new_lv1ptr[0..num_table_entries];
    @memcpy(new_lv1tbl, lv1_table);

    return new_lv1tbl;
}
