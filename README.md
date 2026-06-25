# Melodica Integration into Fife Core

This project integrates the hardware Posit arithmetic unit from **Melodica** into the **Fife RISC-V Core** (from the *Learn Bluespec and RISCV* repository).

## Overview

The core objective of this project is to port the custom posit arithmetic operations from the Melodica hardware into the Fife pipeline, creating a unified RISC-V core capable of executing both standard integer instructions and custom posit arithmetic instructions as a coprocessor or custom-0 extension.

### Original Repositories
- **Melodica**: Provided the Bluespec implementation of the Posit Arithmetic core, specifically `PositCore.bsv` and its associated components for posit formats (posit addition, fused multiply-accumulate, conversion, etc.).
- **Learn Bluespec and RISCV Design (Fife Core)**: Provided the baseline 5-stage RISC-V processor pipeline (`src_Fife`), memory interfaces, and the Verilator/Bluespec simulation environment.

## Integration Structure

The integration involved several key components in `src_Fife`:

1. **`S4_EX_Posit.bsv`**: A wrapper module bridging the Fife execution stage (`EX_to_Retire`) and the Melodica `PositCore`. It handles dispatching custom posit instructions to the posit arithmetic unit, waiting for completion, and propagating the result or exception to the Retire stage.
2. **`Inter_Stage.bsv`**: Expanded to include the new execution pipeline interfaces (`f_RR_to_EX_Posit`, `f_EX_Posit_to_Retire`).
3. **`Fn_Decode.bsv` & `Posit_Instr_Bits.bsv`**: The instruction decoder was modified to identify RISC-V custom-0 instructions (opcode `0x0B`) and correctly extract operand dependencies (`has_rd`, `has_rs1`, `has_rs2`) for the Scoreboard to handle data hazards.
4. **`Fn_Dispatch.bsv`**: Added logic to route the decoded custom-0 instructions to the newly instantiated `S4_EX_Posit` pipeline instead of the standard ALU.

## Building the Project

Ensure you have the **Bluespec Compiler (bsc)**, **Verilator**, and the **RISC-V GNU Toolchain** (`riscv64-unknown-elf-gcc`) installed on your system.

To build the hardware simulator:
```bash
# Navigate to the Fife build directory
cd /teamspace/studios/this_studio/Learn_Bluespec_and_RISCV_Design/Code/Build/Fife

# Compile the Bluespec hardware into Verilog/C++
make v_compile

# Link the C++ modules using Verilator
make v_link
```
This produces the executable simulator binary `exe_Fife_RV32_verilator`.

## Running Test Programs

We have written assembly test programs specifically to test posit arithmetic. They are located in `src_Fife/test_programs/`:
- `posit_basic.S`: Tests basic posit conversions and reads.
- `posit_convert.S`: Tests `pcvtp` (float to posit) and `pcvtf` (posit to float) instructions against edge cases.
- `posit_dot_product.S`: Tests vector dot products using `pfma` (fused multiply-accumulate on the quire) and `prdq` (read quire).

To run a test, follow these steps:

1. **Compile the assembly to machine code (hex)**:
```bash
cd /teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/src_Fife/test_programs/

# Assemble the file
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -c posit_dot_product.S

# Convert to memhex32 format
python3 to_memhex32.py posit_dot_product.o posit_dot_product.memhex32
```

2. **Run the hardware simulation**:
```bash
cd /teamspace/studios/this_studio/Learn_Bluespec_and_RISCV_Design/Code/Build/Fife

# Symlink the generated memhex32 to test.memhex32 (the default loaded file)
ln -s -f /teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/src_Fife/test_programs/posit_dot_product.memhex32 test.memhex32

# Run the simulation. The +tohost flag watches for test completion.
./exe_Fife_RV32_verilator +v2 +tohost
```

If the test is successful, you will see `GPIO tohost PASS` at the end of the output. If a test fails, `GPIO tohost FAIL` will be reported.

### Tracing and Debugging
If a test fails or you want to inspect pipeline states:
```bash
./exe_Fife_RV32_verilator +v2 +tohost +log
```
This will generate a `log.txt` file containing instruction retirement traces, pipeline movements, and Posit unit intermediate calculations.
