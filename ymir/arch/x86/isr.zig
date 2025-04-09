const idt = @import("idt.zig");
const intr = @import("interrupt.zig");

pub const Context = packed struct {
    /// General purpose registers
    registers: Registers,
    /// Interrupt Vector
    vector: u64,
    /// Error Code
    error_code: u64,

    /// CPU status
    rip: u64,
    cs: u64,
    rflags: u64,
};

const Registers = packed struct {
    r8: u64,
    r9: u64,
    r10: u64,
    r11: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
    rdi: u64,
    rsi: u64,
    rbp: u64,
    rsp: u64,
    rbx: u64,
    rdx: u64,
    rcx: u64,
    rax: u64,
};

export fn intrZigEntry(ctx: *Context) callconv(.C) void {
    intr.dispatch(ctx);
}

// 割り込みvectorを受取, そのvectorに対応するISRを生成する
pub fn generateIsr(comptime vector: usize) idt.Isr {
    return struct {
        fn handler() callconv(.Naked) void {
            // Clear the interrupt flag
            // 割り込みを無効化する命令
            asm volatile (
                \\cli
            );
            // If the interrupt does not provide an error code, push a dummy one.
            if (vector != 8 and !(vector >= 10 and vector <= 14) and vector != 17) {
                asm volatile (
                    \\pushq $0
                );
            }
            // Push the vector
            asm volatile (
                \\pushq %[vector]
                :
                : [vector] "n" (vector),
            );
            // Jump to the common ISR
            asm volatile (
                \\jmp isrCommon
            );
        }
    }.handler;
}

export fn isrCommon() callconv(.Naked) void {
    // Save the general-purpose registers
    asm volatile (
        \\pushq %%rax
        \\pushq %%rcx
        \\pushq %%rdx
        \\pushq %%rbx
        \\pushq %%rsp
        \\pushq %%rbp
        \\pushq %%rsi
        \\pushq %%rdi
        \\pushq %%r15
        \\pushq %%r14
        \\pushq %%r13
        \\pushq %%r12
        \\pushq %%r11
        \\pushq %%r10
        \\pushq %%r9
        \\pushq %%r8
    );

    // Push the context and call the handler
    asm volatile (
        \\pushq %%rsp
        \\popq %%rdi
        // Align stack to 16 bytes
        \\pushq %%rsp
        \\pushq (%%rsp)
        \\andq $-0x10, %%rsp
        // call the dispatcher
        \\call intrZigEntry
        // Restore the stack
        \\movq 8(%%rsp), %%rsp
    );

    // Remove general-purpose registers, error code, and vector from the stack
    asm volatile (
        \\popq %%r8
        \\popq %%r9
        \\popq %%r10
        \\popq %%r11
        \\popq %%r12
        \\popq %%r13
        \\popq %%r14
        \\popq %%r15
        \\popq %%rdi
        \\popq %%rsi
        \\popq %%rbp
        \\popq %%rsp
        \\popq %%rbx
        \\popq %%rdx
        \\popq %%rcx
        \\popq %%rax
        \\add   $0x10, %%rsp
        \\iretq
    );
}
