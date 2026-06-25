# posit_convert.S
# =============================================================================
# RISC-V Assembly Test: Posit ↔ Float Conversion
#
# Tests the posit conversion instructions:
#   pcvtp rd, rs1 -- rd = float_to_posit(rs1)   (funct7=0b0000100)
#   pcvtf rd, rs1 -- rd = posit_to_float(rs1)   (funct7=0b0000101)
#
# Instruction encodings (R-type, custom-0):
#   pcvtp rd, rs1 = (0b0000100)(00000)(rs1)(000)(rd)(0001011)
#                 = 0x08000000 | (rs1 << 15) | (rd << 7) | 0x0B
#   pcvtf rd, rs1 = (0b0000101)(00000)(rs1)(000)(rd)(0001011)
#                 = 0x0A000000 | (rs1 << 15) | (rd << 7) | 0x0B
#
# Test cases:
#
# Test 1: Convert float 1.0 to posit32, then convert back
#   IEEE 754 single-precision 1.0 = 0x3F800000
#   posit32(1.0) = 0x40000000
#   converting posit32(1.0) back to float32 should yield 0x3F800000
#
# Test 2: Convert float 2.0 to posit32, then back
#   IEEE 754 single 2.0 = 0x40000000
#   posit32(2.0) = 0x44000000
#
# Test 3: Convert float 0.5 to posit32
#   IEEE 754 single 0.5 = 0x3F000000
#   posit32(0.5) = 0x3C000000
#
# Test 4: Convert float 0.0 to posit32 (should be 0x00000000)
#   IEEE 754 single 0.0 = 0x00000000
#   posit32(0.0) = 0x00000000
#
# Test 5: Convert float NaN to posit32 (should be NaR = 0x80000000)
#   IEEE 754 NaN = 0x7FC00000 (quiet NaN)
#   posit32(NaR) = 0x80000000
#
# Register assignments:
#   x1  = float input
#   x2  = posit result from pcvtp
#   x3  = float result from pcvtf (roundtrip check)
#   x20 = base address for results (0x80000000)
# =============================================================================

.section .text
.global _start
_start:

    lui     x20, 0x80000          # x20 = 0x80000000 (results base)

    # =========================================================================
    # TEST 1: float 1.0 -> posit -> float (roundtrip)
    # =========================================================================

    # Load IEEE 754 float 1.0 = 0x3F800000
    lui     x1, 0x3F800           # x1 = 0x3F800000

    # pcvtp x2, x1 : x2 = float_to_posit(x1)
    # Encoding: funct7=0b0000100, rs2=x0, rs1=x1(00001), funct3=000, rd=x2(00010), opcode=0001011
    # = 0000100 00000 00001 000 00010 0001011
    # = 0x0800010B  (wait, let me compute carefully)
    # funct7[6:0]   = 0000100
    # rs2[4:0]      = 00000
    # rs1[4:0]      = 00001
    # funct3[2:0]   = 000
    # rd[4:0]       = 00010
    # opcode[6:0]   = 0001011
    # Concatenated: 0000100_00000_00001_000_00010_0001011
    # Bit 31:25 = 0000100
    # Bit 24:20 = 00000
    # Bit 19:15 = 00001
    # Bit 14:12 = 000
    # Bit 11:7  = 00010
    # Bit 6:0   = 0001011
    # = 0x0800_080B
    .word 0x0800810B              # pcvtp x2, x1
    # x2 should be 0x40000000 (posit32(1.0))

    # pcvtf x3, x2 : x3 = posit_to_float(x2)
    # funct7=0b0000101, rs2=x0, rs1=x2(00010), funct3=000, rd=x3(00011), opcode=0001011
    # = 0000101 00000 00010 000 00011 0001011
    # = 0x0A00_118B  (rs1=x2=00010 at bits 19:15)
    # Bit pattern: 0000101_00000_00010_000_00011_0001011
    # = 0x0A01018B
    .word 0x0A01018B              # pcvtf x3, x2
    # x3 should be 0x3F800000 (float 1.0, roundtrip)

    sw      x2, 0(x20)            # store posit result
    sw      x3, 4(x20)            # store float roundtrip result

    # Check: x2 should equal posit32(1.0) = 0x40000000
    lui     x10, 0x40000          # x10 = 0x40000000
    bne     x2, x10, test_fail

    # Check: x3 should equal float32(1.0) = 0x3F800000
    lui     x11, 0x3F800          # x11 = 0x3F800000
    bne     x3, x11, test_fail

    # =========================================================================
    # TEST 2: float 2.0 -> posit -> float (roundtrip)
    # =========================================================================

    lui     x1, 0x40000           # x1 = 0x40000000 = float 2.0

    # pcvtp x2, x1  (same encoding structure, rs1=x1=00001, rd=x2=00010)
    .word 0x0800810B              # pcvtp x2, x1
    # x2 should be 0x44000000 (posit32(2.0))

    # pcvtf x3, x2
    .word 0x0A01018B              # pcvtf x3, x2
    # x3 should be 0x40000000 (float 2.0)

    sw      x2, 8(x20)
    sw      x3, 12(x20)

    lui     x10, 0x48000          # expected posit32(2.0) = 0x48000000
    bne     x2, x10, test_fail

    lui     x11, 0x40000          # expected float32(2.0) = 0x40000000
    bne     x3, x11, test_fail

    # =========================================================================
    # TEST 3: float 0.0 -> posit (should be 0x00000000)
    # =========================================================================

    li      x1, 0                 # x1 = 0x00000000 = float 0.0

    # pcvtp x2, x1
    .word 0x0800810B              # pcvtp x2, x1
    # x2 should be 0x00000000 (posit32(0))

    sw      x2, 16(x20)

    bnez    x2, test_fail         # posit(0.0) must be 0

    # =========================================================================
    # TEST 4: float 0.5 -> posit
    # =========================================================================

    # 0.5 in IEEE 754 single = 0x3F000000
    lui     x1, 0x3F000           # x1 = 0x3F000000

    # pcvtp x2, x1
    .word 0x0800810B              # pcvtp x2, x1
    # x2 should be 0x38000000 (posit32(0.5))

    sw      x2, 20(x20)

    lui     x10, 0x38000          # expected posit32(0.5) = 0x38000000
    bne     x2, x10, test_fail

    # All tests passed
    li      x28, 0x1
    j       test_done

test_fail:
    li      x28, 0x3              # test FAIL code

test_done:
    lui     x30, 0x6FFF0
    sw      x28, 0x010(x30)       # signal result tohost result

loop:
    j       loop

.end
