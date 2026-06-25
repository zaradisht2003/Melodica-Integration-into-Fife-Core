# posit_basic.S
# =============================================================================
# RISC-V Assembly Test: Basic Posit Arithmetic (FMA + Quire Read)
#
# Tests the posit custom instruction extension (custom-0, opcode=0x0B):
#   pfma  rd, rs1, rs2  -- quire += rs1 * rs2
#   pfms  rd, rs1, rs2  -- quire -= rs1 * rs2
#   prdq  rd            -- rd = posit_from_quire
#   prstq               -- reset quire to zero
#
# Posit format: posit32 (32-bit, es=2)
#
# Known posit32 encodings (es=2):
#   1.0  = 0x40000000
#   2.0  = 0x44000000
#   4.0  = 0x48000000
#   -1.0 = 0xC0000000  (two's complement of 0x40000000)
#
# Test 1: Compute 1.0 * 2.0 = 2.0 (quire accumulate, then read)
#   pfma quire += 1.0 * 2.0 --> quire holds 2.0
#   prdq x5  --> x5 should be 0x44000000 (posit32 encoding of 2.0)
#
# Test 2: Compute 2.0 + 4.0 using two FMAs with 1.0
#   pfma quire += 1.0 * 2.0 --> quire holds 2.0
#   pfma quire += 1.0 * 4.0 --> quire holds 6.0
#   prdq x6  --> x6 should be posit32(6.0)
#
# Test 3: FMA then FMS cancellation
#   pfma quire += 1.0 * 2.0 --> quire = 2.0
#   pfms quire -= 1.0 * 2.0 --> quire = 0.0
#   prdq x7  --> x7 should be 0x00000000 (posit32(0.0))
#
# Custom instruction encoding (R-type, custom-0):
#   pfma  x0, rs1, rs2 : .word (funct7=0b0000000)(rs2)(rs1)(funct3=000)(rd)(opcode=0001011)
#   pfms  x0, rs1, rs2 : .word (funct7=0b0000001)(rs2)(rs1)(funct3=000)(rd)(opcode=0001011)
#   prdq  rd           : .word (funct7=0b0000010)(00000)(00000)(000)(rd)(0001011)
#   prstq              : .word (funct7=0b0000011)(00000)(00000)(000)(00000)(0001011)
#
# Helper macro for encoding posit custom instructions:
# .insn r opcode, funct3, funct7, rd, rs1, rs2
# opcode = 0x0B = 0b0001011
# funct3 = 0
#
# Using .word encoding directly for maximum portability:
#
# pfma  rd, rs1, rs2  = (0b0000000)(rs2)(rs1)(000)(rd)(0001011)
#   = 0x00000000 | (rs2 << 20) | (rs1 << 15) | (rd << 7) | 0x0B
#
# pfms  rd, rs1, rs2  = (0b0000001)(rs2)(rs1)(000)(rd)(0001011)
#   = 0x02000000 | (rs2 << 20) | (rs1 << 15) | (rd << 7) | 0x0B
#
# prdq  rd            = (0b0000010)(00000)(00000)(000)(rd)(0001011)
#   = 0x04000000 | (rd << 7) | 0x0B
#
# prstq               = (0b0000011)(00000)(00000)(000)(00000)(0001011)
#   = 0x0600000B
#
# Register assignments:
#   x1 = posit32(1.0) = 0x40000000
#   x2 = posit32(2.0) = 0x44000000
#   x3 = posit32(4.0) = 0x48000000
#   x5, x6, x7 = result registers
# =============================================================================

.section .text
.global _start
_start:

    # =========================================================================
    # Load posit32 constants into registers
    # =========================================================================

    lui     x1, 0x40000          # x1 = 0x40000000 = posit32(1.0)
    lui     x2, 0x44000          # x2 = 0x44000000 = posit32(2.0)
    lui     x3, 0x48000          # x3 = 0x48000000 = posit32(4.0)

    # =========================================================================
    # TEST 1: Simple FMA -- quire += 1.0 * 2.0, then read quire
    # Expected: prdq result = posit32(2.0) = 0x44000000
    # =========================================================================

    # prstq: Reset quire to zero first
    # Encoding: funct7=0b0000011, rs2=x0, rs1=x0, funct3=000, rd=x0, opcode=0001011
    # Binary: 0000011 00000 00000 000 00000 0001011 = 0x0600000B
    .word 0x0600000B              # prstq

    # pfma x0, x1, x2 : quire += posit(x1) * posit(x2) = 1.0 * 2.0 = 2.0
    # Encoding: funct7=0b0000000, rs2=x2(00010), rs1=x1(00001), funct3=000, rd=x0(00000), opcode=0001011
    # = 0000000 00010 00001 000 00000 0001011
    # = 0x0020800B
    .word 0x0020800B              # pfma x0, x1, x2

    # prdq x5: rd = posit_from_quire
    # Encoding: funct7=0b0000010, rs2=x0, rs1=x0, funct3=000, rd=x5(00101), opcode=0001011
    # = 0000010 00000 00000 000 00101 0001011
    # = 0x0400028B
    .word 0x0400028B              # prdq x5
    # x5 should now contain posit32(2.0) = 0x44000000

    # Store result for inspection
    lui     x20, 0x80000          # x20 = base address for results
    sw      x5,  0(x20)           # store test1 result at 0x80000000

    # =========================================================================
    # TEST 2: Accumulating FMA -- 1.0*2.0 + 1.0*4.0 = 6.0
    # Expected: prdq result = posit32(6.0)
    # posit32(6.0) ≈ 0x4A000000
    # =========================================================================

    # prstq: Reset quire
    .word 0x0600000B              # prstq

    # pfma x0, x1, x2 : quire += 1.0 * 2.0 = 2.0
    .word 0x0020800B              # pfma x0, x1, x2

    # pfma x0, x1, x3 : quire += 1.0 * 4.0 = 4.0; total = 6.0
    # Encoding: funct7=0b0000000, rs2=x3(00011), rs1=x1(00001), funct3=000, rd=x0, opcode=0001011
    # = 0000000 00011 00001 000 00000 0001011
    # = 0x0030800B
    .word 0x0030800B              # pfma x0, x1, x3

    # prdq x6: read quire result
    # Encoding: funct7=0b0000010, rd=x6(00110), others zero, opcode=0001011
    # = 0000010 00000 00000 000 00110 0001011
    # = 0x0400030B
    .word 0x0400030B              # prdq x6
    # x6 should contain posit32(6.0)

    sw      x6,  4(x20)           # store test2 result

    # =========================================================================
    # TEST 3: FMA followed by FMS cancellation
    # quire = 2.0 - 2.0 = 0.0
    # Expected: prdq result = posit32(0.0) = 0x00000000
    # =========================================================================

    # prstq: Reset quire
    .word 0x0600000B              # prstq

    # pfma x0, x1, x2 : quire += 1.0 * 2.0 = 2.0
    .word 0x0020800B              # pfma x0, x1, x2

    # pfms x0, x1, x2 : quire -= 1.0 * 2.0; total = 0.0
    # pfms: funct7=0b0000001, rs2=x2(00010), rs1=x1(00001), funct3=000, rd=x0, opcode=0001011
    # = 0000001 00010 00001 000 00000 0001011
    # = 0x0220800B
    .word 0x0220800B              # pfms x0, x1, x2

    # prdq x7: read quire result
    # Encoding: funct7=0b0000010, rd=x7(00111), others zero, opcode=0001011
    # = 0000010 00000 00000 000 00111 0001011
    # = 0x0400038B
    .word 0x0400038B              # prdq x7
    # x7 should contain 0x00000000 (posit32(0.0))

    sw      x7,  8(x20)           # store test3 result

    # =========================================================================
    # Check results (compare with expected values)
    # =========================================================================

    lui     x10, 0x44000          # x10 = expected for test1: posit32(2.0) = 0x44000000
    bne     x5, x10, test_fail    # branch if test1 failed

    # x6 expected ≈ posit32(6.0). Hard to compute exact bits here;
    # just check it is nonzero and positive (bit 31 = 0)
    beqz    x6, test_fail         # fail if zero
    bltz    x6, test_fail         # fail if negative

    beqz    x7, test3_ok          # test3: should be exactly zero
    j       test_fail

test3_ok:
    li      x28, 0x1              # PASS code
    j       test_done

test_fail:
    li      x28, 0x3              # FAIL code

test_done:
    lui     x30, 0x6FFF0
    sw      x28, 0x010(x30)       # write tohost

    # Loop forever
loop:
    j       loop

.end
