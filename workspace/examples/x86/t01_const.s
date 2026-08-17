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


.globl main
main:
    pushq %rbp
    movq %rsp, %rbp
    movq $42, %rax
    movq %rax, %rdi
    xorq %rax, %rax
    callq print
    popq %rbp
    retq
    popq %rbp
    retq