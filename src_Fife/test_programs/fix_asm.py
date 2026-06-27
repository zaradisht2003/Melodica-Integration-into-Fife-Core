import os
import glob
import re

def encode_posit(funct7, rs2, rs1, funct3, rd):
    opcode = 0x0B
    inst = (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
    return f"0x{inst:08X}"

fixes = {
    # pfma x0, x1, x2
    "0x0020080B": encode_posit(0, 2, 1, 0, 0),
    # prdq x5
    "0x0400028B": encode_posit(2, 0, 0, 0, 5),

    # prdq x6
    "0x0400030B": encode_posit(2, 0, 0, 0, 6),
    # pfms x0, x1, x2
    "0x0220080B": encode_posit(1, 2, 1, 0, 0),
    # prdq x7
    "0x0400038B": encode_posit(2, 0, 0, 0, 7),
    
    # pcvtp x2, x1
    "0x0800080B": encode_posit(4, 0, 1, 0, 2),
    # pcvtf x3, x2
    "0x0A01018B": encode_posit(5, 0, 2, 0, 3),

    # pfma x0, x2, x3
    "0x0031000B": encode_posit(0, 3, 2, 0, 0),
    # pfma x0, x1, x3
    "0x0030800B": encode_posit(0, 3, 1, 0, 0),
    # pfma x0, x13, x14
    "0x00E6800B": encode_posit(0, 14, 13, 0, 0),
    # prdq x15
    "0x0400078B": encode_posit(2, 0, 0, 0, 15),
    # prdq x16
    "0x0400080B": encode_posit(2, 0, 0, 0, 16),
}

for fname in glob.glob("*.S"):
    with open(fname, "r") as f:
        content = f.read()
    
    for old, new in fixes.items():
        content = content.replace(old, new)
        content = content.replace(old.lower(), new)
        
    with open(fname, "w") as f:
        f.write(content)

print("Files fixed.")
