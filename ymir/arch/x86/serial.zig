const am = @import("asm.zig");
const ymir = @import("ymir");
const serial = ymir.serial;

pub const Ports = enum(u16) {
    com1 = 0x3F8,
    com2 = 0x2F8,
    com3 = 0x3E8,
    com4 = 0x2E8,
};

// refer UART Registers from https://en.wikibooks.org/wiki/Serial_Programming/8250_UART_Programming
const offsets = struct {
    pub const txr = 0;
    pub const rxr = 0;
    pub const dll = 0;
    pub const ier = 1;
    pub const dlh = 1;
    pub const iir = 2;
    pub const fcr = 2;
    pub const lcr = 3;
    pub const mcr = 4;
    pub const lsr = 5;
    pub const msr = 6;
    pub const sr = 7;
};

pub fn initSerial(serial: *Serial, port: Ports, baud: u32) void {
    // レジスタの設定
    const p = @intFromEnum(port);
    am.outb(0b00_000_0_00, p + offsets.lcr); // LCR(Line Protocol)の初期化
    am.outb(0, p + offsets.ier); // IER(有効化する割り込み)を無効化
    am.outb(0, p + offsets.fcr); // FIFOバッファを無効化

    // Baud Rateの設定
    const divisor = 115200 / baud;
    const c = am.inb(p + offsets.lcr);
    am.outb(c | 0b1000_0000, p + offsets.lcr); // Enable DLAB
    am.outb(@truncate(divisor & 0xFF), p + offsets.dll);
    am.outb(@truncate((divisor >> 8) & 0xFF), p + offsets.dlh);
    am.outb(c & 0b0111_1111, p + offsets.lcr); // Disable DLAB

    // write_fnの登録
    serial._write_fn = switch (port) {
        .com1 => writeByteCom1,
        .com2 => writeByteCom2,
        .com3 => writeByteCom3,
        .com4 => writeByteCom4,
    };
}

// const bits = ymir.bits;
pub fn writeByte(byte: u8, port: Ports) void {
    // NOTE:シリアルに書き込むためには、TX-buferが空になるのを待つ必要がある
    //      TX-bufferが空かどうかは、LSRのTHRE bitで確認できる
    //      もし空でなかったら、空になるまで待つ
    //      THRE bitは5bit目なので、5bit目が立ってるかを確認する
    while ((am.inb(@intFromEnum(port) + offsets.lsr) & 0b0010_0000) == 0) {
        am.relax();
    }

    // Put char into the transmitter holding buffer
    am.outb(byte, @intFromEnum(port));
}

fn writeByteCom1(byte: u8) void {
    writeByte(byte, .com1);
}

fn writeByteCom2(byte: u8) void {
    writeByte(byte, .com2);
}

fn writeByteCom3(byte: u8) void {
    writeByte(byte, .com3);
}

fn writeByteCom4(byte: u8) void {
    writeByte(byte, .com4);
}
