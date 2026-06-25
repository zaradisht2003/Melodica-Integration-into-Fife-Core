# posit_dot_product.S
# =============================================================================
# RISC-V Assembly Test: Dot Product of Two Vectors Using Posit FMA
#
# Computes dot_product(A, B) = sum(A[i] * B[i]) for i=0..3
# using posit32 arithmetic with the quire accumulator.
#
# This is the primary use case for posit arithmetic:
#   - Load posit values for A[] and B[] from memory
#   - Execute pfma for each pair (quire += A[i] * B[i])
#   - Execute prdq to read the final accumulated result
#
# Test vector (posit32 values):
#   A = [1.0, 2.0, 3.0, 4.0]
#       = [0x40000000, 0x44000000, 0x46000000, 0x48000000]
#   B = [1.0, 2.0, 3.0, 4.0]
#       = [0x40000000, 0x44000000, 0x46000000, 0x48000000]
#   dot(A, B) = 1 + 4 + 9 + 16 = 30.0
#
# posit32(3.0)  = 0x46000000
# posit32(30.0) ≈ 0x4F000000  (approximate; exact bits from posit standard)
#
# Custom instructions used:
#   prstq : reset quire  (0x0600000B)
#   pfma x0, rs1, rs2    : quire += rs1 * rs2
#   prdq rd              : rd = posit_from_quire
#
# pfma encoding: (0b0000000)(rs2<<20)|(rs1<<15)|(rd<<7)|0x0B
#
# Register map:
#   x10 = pointer to vector A
#   x11 = pointer to vector B
#   x12 = loop counter (4 iterations)
#   x13 = A[i] (posit32 value)
#   x14 = B[i] (posit32 value)
#   x15 = dot product result (from prdq)
#   x20 = results base address
#   x21 = vector data storage area
#
# Memory layout (starting at DATA_BASE):
#   [0] = A[0] = 0x40000000 (1.0)
#   [4] = A[1] = 0x44000000 (2.0)
#   [8] = A[2] = 0x46000000 (3.0)
#  [12] = A[3] = 0x48000000 (4.0)
#  [16] = B[0] = 0x40000000 (1.0)
#  [20] = B[1] = 0x44000000 (2.0)
#  [24] = B[2] = 0x46000000 (3.0)
#  [28] = B[3] = 0x48000000 (4.0)
# =============================================================================

.section .text
.global _start
_start:
    j real_start

.align 4
# Vector A: posit32 values [1.0, 2.0, 3.0, 4.0]
vec_A:
    .word 0x40000000    # posit32(1.0)
    .word 0x48000000    # posit32(2.0)
    .word 0x4C000000    # posit32(3.0)
    .word 0x50000000    # posit32(4.0)

# Vector B: posit32 values [1.0, 2.0, 3.0, 4.0]
vec_B:
    .word 0x40000000    # posit32(1.0)
    .word 0x48000000    # posit32(2.0)
    .word 0x4C000000    # posit32(3.0)
    .word 0x50000000    # posit32(4.0)

real_start:

    # =========================================================================
    # Reset the quire before starting accumulation
    # =========================================================================
    .word 0x0600000B              # prstq: quire = 0

    # =========================================================================
    # Load vector pointers
    # =========================================================================
    la      x10, vec_A            # x10 = &A[0]
    la      x11, vec_B            # x11 = &B[0]
    li      x12, 4                # x12 = loop count (4 elements)

    # =========================================================================
    # Dot product loop: quire += A[i] * B[i]
    # =========================================================================
dot_loop:
    beqz    x12, dot_done         # if count == 0, done

    lw      x13, 0(x10)           # x13 = A[i]
    lw      x14, 0(x11)           # x14 = B[i]

    # pfma x0, x13, x14 : quire += x13 * x14
    .word 0x00E6800B              # pfma x0, x13, x14

    addi    x10, x10, 4           # A++
    addi    x11, x11, 4           # B++
    addi    x12, x12, -1          # count--
    j       dot_loop

dot_done:
    # prdq x15 : x15 = posit_from_quire
    .word 0x0400078B              # prdq x15
    # x15 should be approx 30.0 = 0x63800000

    lui     s4, 0x80000
    sw      x15, 0(s4)            # store dot_product result

    # Check if dot product > 0
    beqz    x15, test_fail
    bltz    x15, test_fail

    # Check if dot product ≈ 30.0
    lui     a0, 0x60000           # lower bound: 16.0
    lui     a1, 0x68000           # upper bound: 64.0
    blt     x15, a0, test_fail
    bge     x15, a1, test_fail

    # =========================================================================
    # Store and validate result
    # =========================================================================
    lui     x20, 0x80000          # results base address

    # Validate: dot product should be positive (bit 31 = 0) and nonzero
    beqz    x15, test_fail        # fail if zero
    bltz    x15, test_fail        # fail if negative (NaR)

    # Optional: check approximate value
    lui     x10, 0x60000          # lower bound: posit32(16.0) = 0x60000000
    lui     x11, 0x68000          # upper bound: posit32(64.0) = 0x68000000
    blt     x15, x10, test_fail   # fail if result < 16.0
    bge     x15, x11, test_fail   # fail if result >= 64.0

    # =========================================================================
    # Bonus test: dot product with mixed signs
    # dot([1.0, -1.0], [2.0, 2.0]) = 2.0 - 2.0 = 0.0
    # =========================================================================
    .word 0x0600000B              # prstq: reset quire

    lui     x1, 0x40000           # x1 = posit32(1.0)  = 0x40000000
    lui     x2, 0xC0000           # x2 = posit32(-1.0) = 0xC0000000
    lui     x3, 0x48000           # x3 = posit32(2.0)  = 0x48000000

    # pfma x0, x1, x3 : quire += 1.0 * 2.0 = 2.0
    # rs1=x1(00001), rs2=x3(00011), rd=x0(00000)
    # = 0000000 00011 00001 000 00000 0001011
    # = 0x0030_080B
    .word 0x0030800B              # pfma x0, x1, x3

    # pfma x0, x2, x3 : quire += -1.0 * 2.0 = -2.0; total = 0.0
    # rs1=x2(00010), rs2=x3(00011), rd=x0(00000)
    # = 0000000 00011 00010 000 00000 0001011
    # = 0x0031_000B
    .word 0x0031000B              # pfma x0, x2, x3

    # prdq x16 : x16 = posit_from_quire
    # rd=x16(10000), others 0
    # = 0000010 00000 00000 000 10000 0001011
    # = 0x0400_080B
    .word 0x0400080B              # prdq x16
    # x16 should be 0x00000000 (posit32(0.0))

    sw      x16, 4(x20)
    bnez    x16, test_fail        # zero dot product check

    # =========================================================================
    # All tests passed
    # =========================================================================
    li      x28, 0x1
    j       test_done

test_fail:
    li      x28, 0x3              # test FAIL code

test_done:
    lui     x30, 0x6FFF0
    sw      x28, 0x010(x30)       # signal result tohost

loop:
    j       loop

.end
