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


.globl add
add:
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
    addq %r11, %rax
    popq %rbx
    popq %r12
    popq %rbp
    retq
    popq %rbx
    popq %r12
    popq %rbp
    retq

.globl main
main:
    pushq %rbp
    movq %rsp, %rbp
    movq $3, %rax
    movq %rax, %rdi
    movq $4, %rax
    movq %rax, %rsi
    xorq %rax, %rax
    callq add
    movq %rax, %rdi
    xorq %rax, %rax
    callq print
    popq %rbp
    retq
    popq %rbp
    retq