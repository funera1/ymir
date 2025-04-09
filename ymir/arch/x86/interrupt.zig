const isr = @import("isr.zig");
const idt = @import("idt.zig");
const am = @import("asm.zig");
const ymir = @import("ymir");
const std = @import("std");
const log = std.log.scoped(.ymir);
const Context = isr.Context;

pub const Handler = *const fn (*Context) void;
var handlers: [256]Handler = [_]Handler{unhandledHandler} ** 256;

pub fn dispatch(context: *Context) void {
    const vector = context.vector;
    handlers[vector](context);
}

fn unhandledHandler(context: *Context) void {
    @setCold(true);

    log.err("============ Oops! ===================", .{});
    log.err("Unhandled interrupt: {s} ({})", .{
        exceptionName(context.vector),
        context.vector,
    });
    log.err("Error Code: 0x{X}", .{context.error_code});
    log.err("RIP    : 0x{X:0>16}", .{context.rip});
    log.err("EFLAGS : 0x{X:0>16}", .{context.rflags});
    log.err("RAX    : 0x{X:0>16}", .{context.registers.rax});
    log.err("RBX    : 0x{X:0>16}", .{context.registers.rbx});
    log.err("RCX    : 0x{X:0>16}", .{context.registers.rcx});
    log.err("RDX    : 0x{X:0>16}", .{context.registers.rdx});
    log.err("RSI    : 0x{X:0>16}", .{context.registers.rsi});
    log.err("RDI    : 0x{X:0>16}", .{context.registers.rdi});
    log.err("RSP    : 0x{X:0>16}", .{context.registers.rsp});
    log.err("RBP    : 0x{X:0>16}", .{context.registers.rbp});
    log.err("R8     : 0x{X:0>16}", .{context.registers.r8});
    log.err("R9     : 0x{X:0>16}", .{context.registers.r9});
    log.err("R10    : 0x{X:0>16}", .{context.registers.r10});
    log.err("R11    : 0x{X:0>16}", .{context.registers.r11});
    log.err("R12    : 0x{X:0>16}", .{context.registers.r12});
    log.err("R13    : 0x{X:0>16}", .{context.registers.r13});
    log.err("R14    : 0x{X:0>16}", .{context.registers.r14});
    log.err("R15    : 0x{X:0>16}", .{context.registers.r15});
    log.err("CS     : 0x{X:0>4}", .{context.cs});

    ymir.endlessHalt();
}

pub fn init() void {
    inline for (0..idt.max_num_gates) |i| {
        idt.setGate(
            i,
            .Interrupt64,
            isr.generateIsr(i),
        );
    }
    idt.init();
    am.sti();
}

// Exception vectors.
const divide_by_zero = 0;
const debug = 1;
const non_maskable_interrupt = 2;
const breakpoint = 3;
const overflow = 4;
const bound_range_exceeded = 5;
const invalid_opcode = 6;
const device_not_available = 7;
const double_fault = 8;
const coprocessor_segment_overrun = 9;
const invalid_tss = 10;
const segment_not_present = 11;
const stack_segment_fault = 12;
const general_protection_fault = 13;
const page_fault = 14;
const floating_point_exception = 16;
const alignment_check = 17;
const machine_check = 18;
const simd_exception = 19;
const virtualization_exception = 20;
const control_protection_excepton = 21;

pub const num_system_exceptions = 32;

/// Get the name of an exception.
pub inline fn exceptionName(vector: u64) []const u8 {
    return switch (vector) {
        divide_by_zero => "#DE: Divide by zero",
        debug => "#DB: Debug",
        non_maskable_interrupt => "NMI: Non-maskable interrupt",
        breakpoint => "#BP: Breakpoint",
        overflow => "#OF: Overflow",
        bound_range_exceeded => "#BR: Bound range exceeded",
        invalid_opcode => "#UD: Invalid opcode",
        device_not_available => "#NM: Device not available",
        double_fault => "#DF: Double fault",
        coprocessor_segment_overrun => "Coprocessor segment overrun",
        invalid_tss => "#TS: Invalid TSS",
        segment_not_present => "#NP: Segment not present",
        stack_segment_fault => "#SS: Stack-segment fault",
        general_protection_fault => "#GP: General protection fault",
        page_fault => "#PF: Page fault",
        floating_point_exception => "#MF: Floating-point exception",
        alignment_check => "#AC: Alignment check",
        machine_check => "#MC: Machine check",
        simd_exception => "#XM: SIMD exception",
        virtualization_exception => "#VE: Virtualization exception",
        control_protection_excepton => "#CP: Control protection exception",
        else => "Unknown exception",
    };
}
