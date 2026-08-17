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


.globl factorial
factorial:
    pushq %rbp
    movq %rsp, %rbp
    pushq %rbx
    subq $8, %rsp
    movq %rdi, %rbx
    movq %rbx, %rax
    pushq %rax
    movq $0, %rax
    popq %r11
    cmpq %rax, %r11
    sete %al
    movzbq %al, %rax
    testq %rax, %rax
    jne .L_if_true_0
    jmp .L_if_false_1
.L_if_true_0:
    movq $1, %rax
    addq $8, %rsp
    popq %rbx
    popq %rbp
    retq
    jmp .L_if_end_2
.L_if_false_1:
    movq %rbx, %rax
    pushq %rax
    subq $8, %rsp
    movq %rbx, %rax
    pushq %rax
    movq $1, %rax
    popq %r11
    negq %rax
    addq %r11, %rax
    movq %rax, %rdi
    xorq %rax, %rax
    callq factorial
    addq $8, %rsp
    popq %r11
    imulq %r11, %rax
    addq $8, %rsp
    popq %rbx
    popq %rbp
    retq
.L_if_end_2:
    addq $8, %rsp
    popq %rbx
    popq %rbp
    retq

.globl factorialIter
factorialIter:
    pushq %rbp
    movq %rsp, %rbp
    pushq %r12
    pushq %rbx
    movq %rdi, %r12
    movq $1, %rax
    movq %rax, %rbx
    movq %r12, %rax
    movq %rax, %r12
.L_while_head_0:
    movq %r12, %rax
    pushq %rax
    movq $0, %rax
    popq %r11
    cmpq %rax, %r11
    setg %al
    movzbq %al, %rax
    testq %rax, %rax
    jne .L_while_body_1
    jmp .L_while_exit_2
.L_while_body_1:
    movq %rbx, %rax
    pushq %rax
    movq %r12, %rax
    popq %r11
    imulq %r11, %rax
    movq %rax, %rbx
    movq %r12, %rax
    pushq %rax
    movq $1, %rax
    popq %r11
    negq %rax
    addq %r11, %rax
    movq %rax, %r12
    jmp .L_while_head_0
.L_while_exit_2:
    movq %rbx, %rax
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
    pushq %rbx
    subq $8, %rsp
    movq $0, %rax
    movq %rax, %rbx
    xorq %rax, %rax
    callq read_int
    movq %rax, %rbx
    movq %rbx, %rax
    movq %rax, %rdi
    xorq %rax, %rax
    callq factorial
    movq %rax, %rdi
    xorq %rax, %rax
    callq print
    movq %rbx, %rax
    movq %rax, %rdi
    xorq %rax, %rax
    callq factorialIter
    movq %rax, %rdi
    xorq %rax, %rax
    callq print
    addq $8, %rsp
    popq %rbx
    popq %rbp
    retq