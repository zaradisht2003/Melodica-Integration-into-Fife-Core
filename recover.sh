cat << 'EOF' > Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs/posit_mac_loop.S
# posit_mac_loop.S
.section .text
.global _start
_start:
    j real_start

real_start:
    .word 0x0600000B              # prstq
    li      x12, 100
    lui     x13, 0x40000
    lui     x14, 0x48000
dot_loop:
    .word 0x00E6800B              # pfma x0, x13, x14
    addi    x12, x12, -1
    bnez    x12, dot_loop

    .word 0x0400078B              # prdq x15
    li      x28, 0x1
    lui     x30, 0x6FFF0
    sw      x28, 0x010(x30)
loop:
    j       loop
.end
EOF
cat << 'EOF' > Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs/posit_matmul.S
# posit_matmul.S
.section .text
.global _start
_start:
    j real_start

real_start:
    li      x10, 10               # outer loop
outer_loop:
    .word 0x0600000B              # prstq
    li      x11, 10               # inner loop
    lui     x13, 0x40000
    lui     x14, 0x40000
inner_loop:
    .word 0x00E6800B              # pfma x0, x13, x14
    addi    x11, x11, -1
    bnez    x11, inner_loop

    .word 0x0400078B              # prdq x15
    addi    x10, x10, -1
    bnez    x10, outer_loop

    li      x28, 0x1
    lui     x30, 0x6FFF0
    sw      x28, 0x010(x30)
loop:
    j       loop
.end
EOF
cat << 'EOF' > Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs/posit_poly_eval.S
# posit_poly_eval.S
.section .text
.global _start
_start:
    j real_start

real_start:
    li      x10, 20               # 20 points
point_loop:
    li      x11, 5                # degree 5
    lui     x13, 0x40000          # x value
    .word 0x0600000B              # prstq
    lui     x14, 0x40000
    .word 0x00E7000B              # pfma x0, x14, x14 
poly_loop:
    .word 0x0400078B              # prdq x15
    .word 0x0600000B              # prstq
    .word 0x00F6800B              # pfma x0, x13, x15  
    lui     x14, 0x40000
    .word 0x00E7000B              # pfma x0, x14, x14
    addi    x11, x11, -1
    bnez    x11, poly_loop

    addi    x10, x10, -1
    bnez    x10, point_loop

    li      x28, 0x1
    lui     x30, 0x6FFF0
    sw      x28, 0x010(x30)
loop:
    j       loop
.end
EOF
cat << 'EOF' > Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs/posit_conv1d.S
# posit_conv1d.S
.section .text
.global _start
_start:
    j real_start

.align 4
data_arr:
    .word 0x40000000, 0x44000000, 0x46000000, 0x48000000, 0x4A000000, 0x4C000000, 0x4E000000, 0x50000000
kernel_arr:
    .word 0x40000000, 0x44000000, 0x46000000

real_start:
    li      x10, 5                # output elements (8 - 3)
    la      x20, data_arr
conv_loop:
    .word 0x0600000B              # prstq
    li      x11, 3                # kernel size
    mv      x21, x20              # window start
    la      x22, kernel_arr
inner_conv:
    lw      x13, 0(x21)
    lw      x14, 0(x22)
    .word 0x00E6800B              # pfma x0, x13, x14
    addi    x21, x21, 4
    addi    x22, x22, 4
    addi    x11, x11, -1
    bnez    x11, inner_conv

    .word 0x0400078B              # prdq x15
    addi    x20, x20, 4
    addi    x10, x10, -1
    bnez    x10, conv_loop

    li      x28, 0x1
    lui     x30, 0x6FFF0
    sw      x28, 0x010(x30)
loop:
    j       loop
.end
EOF
cat << 'EOF' > Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs/posit_iir_filter.S
# posit_iir_filter.S
.section .text
.global _start
_start:
    j real_start

real_start:
    li      x10, 50               # 50 samples
    lui     x13, 0x30000          # alpha = 0.5
    lui     x15, 0x00000          # y_prev = 0
iir_loop:
    .word 0x0600000B              # prstq
    lui     x14, 0x40000          # x_curr = 1.0
    lui     x16, 0x40000
    .word 0x0107000B              # pfma x0, x14, x16
    .word 0x00F6800B              # pfma x0, x13, x15
    .word 0x0400078B              # prdq x15

    addi    x10, x10, -1
    bnez    x10, iir_loop

    li      x28, 0x1
    lui     x30, 0x6FFF0
    sw      x28, 0x010(x30)
loop:
    j       loop
.end
EOF