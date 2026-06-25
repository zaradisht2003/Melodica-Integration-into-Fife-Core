import sys
import subprocess
import re

if len(sys.argv) != 3:
    print("Usage: python3 to_memhex32.py <input.o> <output.memhex32>")
    sys.exit(1)

input_o = sys.argv[1]
output_hex = sys.argv[2]

# Run objcopy to binary, then read binary
subprocess.run(['riscv64-unknown-elf-ld', '-m', 'elf32lriscv', '-Ttext', '0x80000000', input_o, '-o', 'tmp.elf'])
subprocess.run(['riscv64-unknown-elf-objcopy', '-O', 'binary', 'tmp.elf', 'tmp.bin'])

with open('tmp.bin', 'rb') as f:
    data = f.read()

# Pad to multiple of 4
while len(data) % 4 != 0:
    data += b'\x00'

words = []
for i in range(0, len(data), 4):
    word = int.from_bytes(data[i:i+4], byteorder='little')
    words.append(word)

with open(output_hex, 'w') as f:
    f.write("@20000000\n")
    for w in words:
        f.write(f"{w:08X}\n")

print(f"Generated {output_hex}")
