.section .note.GNU-stack,"",@progbits

.section .rodata
.fmt_out:  .string "%d\n"
.fmt_in:   .string "%d"
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
    movq %rax, %r11
    movq $0, %rax
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
.L_if_false_1:
    movq %rbx, %rax
    movq %rax, %r11
    movq %rbx, %rax
    movq %rax, %r11
    movq $1, %rax
    negq %rax
    addq %r11, %rax
    movq %rax, %rdi
    xorq %rax, %rax
    callq factorial
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

.globl main
main:
    pushq %rbp
    movq %rsp, %rbp
    pushq %rbx
    pushq %r12
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
    movq %rax, %r12
    movq $1, %rax
    movq %rax, %rbx
    movq %r12, %rax
    movq %rax, %r12
.L_while_head_0_il0:
    movq %r12, %rax
    movq %rax, %r11
    movq $0, %rax
    cmpq %rax, %r11
    setg %al
    movzbq %al, %rax
    testq %rax, %rax
    jne .L_while_body_1_il0
    jmp .L_while_exit_2_il0
.L_while_body_1_il0:
    movq %r12, %rax
    movq %rax, %rbx
    movq %r12, %rax
    movq %rax, %r11
    movq $1, %rax
    negq %rax
    addq %r11, %rax
    movq %rax, %r12
    jmp .L_while_head_0_il0
.L_while_exit_2_il0:
    movq %rbx, %rax
    movq %rax, %rbx
    jmp .L_L_il_exit_il0
.L_L_il_exit_il0:
    movq %rbx, %rax
    movq %rax, %rdi
    xorq %rax, %rax
    callq print
    popq %r12
    popq %rbx
    popq %rbp
    retq