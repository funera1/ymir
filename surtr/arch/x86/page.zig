const std = @import("std");
const uefi = std.os.uefi;
const BootServices = uefi.tables.BootServices;
const TableLevel = enum{ lv4, lv3, lv2, lv1 };

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
            return Self {
                .present = present,
                .rw = true,
                .us = false,
                // ページをマップするため、.ps = true
                .ps = true,
                .phys = @truncate(phys>>12),
            };
        }

        // ページエントリを参照するエントリを作成する関数
        pub fn newMapTable(table: [*]LowerType, present: bool) Self {
            if (level == .lv1) @compileError("Lv1 entry cannot reference a page table");
            return Self {
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

pub const Phys = u64;
pub const Virt = u64;

const page_mask_4k: u64 = 0xFFF;
const num_table_entries: usize = 512;

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

const am = @import("asm.zig");

pub const PageAttribute = enum {
    /// RO
    read_only,
    /// RW
    read_write,
    /// RX
    executable,
};

pub const PageError = error{ NoMemory, NotPresent, NotCanonical, InvalidAddress, AlreadyMapped };

pub const kib = 1024;
pub const page_size_4k = 4 * kib;

fn allocateNewTable(T: type, entry: *T, bs: *BootServices) PageError!void {
    var ptr: Phys = undefined;
    const status = bs.allocatePages(.AllocateAnyPages, .BootServicesData, 1, @ptrCast(&ptr));
    if (status != .Success) return PageError.NoMemory;

    clearPage(ptr);
    entry.* = T.newMapTable(@ptrFromInt(ptr), true);
}

// 対象ページを0埋めする
fn clearPage(addr: Phys) void {
    const page_ptr: [*]u8 = @ptrFromInt(addr);
    @memset(page_ptr[0..page_size_4k], 0);
}

// 4KiBページをマップする関数
pub fn map4kTo(virt: Virt, phys: Phys, attr: PageAttribute, bs: *BootServices) PageError!void {
    const rw = switch (attr) {
        .read_only, .executable => false,
        .read_write => true,
    };

    // 4段のページテーブルをたどっている
    const lv4ent = getLv4Entry(virt, am.readCr3());
    if (!lv4ent.present) try allocateNewTable(Lv4Entry, lv4ent, bs);

    const lv3ent = getLv3Entry(virt, lv4ent.address());
    if (!lv3ent.present) try allocateNewTable(Lv3Entry, lv3ent, bs);

    const lv2ent = getLv2Entry(virt, lv3ent.address());
    if (!lv2ent.present) try allocateNewTable(Lv2Entry, lv2ent, bs);

    const lv1ent = getLv1Entry(virt, lv2ent.address());
    if (lv1ent.present) return PageError.AlreadyMapped;

    // 新しいページをマップ
    var new_lv1ent = Lv1Entry.newMapPage(phys, true);
    new_lv1ent.rw = rw;
    lv1ent.* = new_lv1ent;
    // No need to flush TLB because the page was not present before.
}

pub fn setLv4Writable(bs: *BootServices) PageError!void {
    var new_lv4ptr: [*]Lv4Entry = undefined;
    const status = bs.allocatePages(.AllocateAnyPages, .BootServicesData, 1, @ptrCast(&new_lv4ptr));
    if (status != .Success) return PageError.NoMemory;

    const new_lv4tbl = new_lv4ptr[0..num_table_entries];
    const lv4tbl = getLv4Table(am.readCr3());
    @memcpy(new_lv4tbl, lv4tbl);

    am.loadCr3(@intFromPtr(new_lv4tbl.ptr));
}