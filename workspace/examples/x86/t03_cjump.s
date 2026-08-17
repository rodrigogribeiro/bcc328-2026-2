.section .note.GNU-stack,"",@progbits

.section .rodata
.fmt_out:  .string "%d\n"
.fmt_in:   .string "%d"

.section .bss
.scan_buf: .quad 0

.section .text

# print(val) -> void  [val in %rdi]
print:
    pushq %rbp
    movq %rsp, %rbp
    movq %rdi, %rsi
    leaq .fmt_out(%rip), %rdi
    xorq %rax, %rax
    callq printf
    popq %rbp
    retq

# read_int() -> int  [result in %rax]
read_int:
    pushq %rbp
    movq %rsp, %rbp
    leaq .fmt_in(%rip), %rdi
    leaq .scan_buf(%rip), %rsi
    xorq %rax, %rax
    callq scanf
    movq .scan_buf(%rip), %rax
    popq %rbp
    retq

# alloc(n) -> ptr  [n in %rdi]
alloc:
    pushq %rbp
    movq %rsp, %rbp
    imulq $8, %rdi
    callq malloc
    popq %rbp
    retq


.globl max
max:
    pushq %rbp
    movq %rsp, %rbp
    pushq %r12
    pushq %rbx
    movq %rdi, %r12
    movq %rsi, %rbx
    movq %r12, %rax
    pushq %rax
    movq %rbx, %rax
    popq %r11
    cmpq %rax, %r11
    setge %al
    movzbq %al, %rax
    testq %rax, %rax
    jne .L_then_0
    jmp .L_else_1
.L_then_0:
    movq %r12, %rax
    popq %rbx
    popq %r12
    popq %rbp
    retq
.L_else_1:
    movq %rbx, %rax
    popq %rbx
    popq %r12
    popq %rbp
    retq
.L_end_2:
    popq %rbx
    popq %r12
    popq %rbp
    retq

.globl main
main:
    pushq %rbp
    movq %rsp, %rbp
    movq $10, %rax
    movq %rax, %rdi
    movq $7, %rax
    movq %rax, %rsi
    xorq %rax, %rax
    callq max
    movq %rax, %rdi
    xorq %rax, %rax
    callq print
    movq $3, %rax
    movq %rax, %rdi
    movq $9, %rax
    movq %rax, %rsi
    xorq %rax, %rax
    callq max
    movq %rax, %rdi
    xorq %rax, %rax
    callq print
    popq %rbp
    retq
    popq %rbp
    retq