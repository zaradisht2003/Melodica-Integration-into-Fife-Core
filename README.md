# Melodica Integration into Fife Core

This project integrates the hardware Posit arithmetic unit from **Melodica** into the **Fife RISC-V Core** (from the *Learn Bluespec and RISCV* repository).

## Overview

The core objective of this project is to port the custom posit arithmetic operations from the Melodica hardware into the Fife pipeline, creating a unified RISC-V core capable of executing both standard integer instructions and custom posit arithmetic instructions as a coprocessor or custom-0 extension.

### Original Repositories
- **Melodica**: Provided the Bluespec implementation of the Posit Arithmetic core, specifically `PositCore.bsv` and its associated components for posit formats (posit addition, fused multiply-accumulate, conversion, etc.).
- **Learn Bluespec and RISCV Design (Fife Core)**: Provided the baseline 5-stage RISC-V processor pipeline (`src_Fife`), memory interfaces, and the Verilator/Bluespec simulation environment.

## 1. Architectural Integration (Bluespec Codebase)

The first phase of the port involved integrating the standalone `PositCore` unit into the Fife pipeline, creating a custom execution path in `src_Fife`.

### Execution Stage Wrappers
We created **`S4_EX_Posit.bsv`**, which serves as a wrapper module that bridges the standard Fife execution stages (`EX_to_Retire`) with the Melodica `PositCore`. 
- **Dispatch:** It accepts custom posit instructions containing specific operands and forwards them into `PositCore`.
- **Synchronization:** It waits for the multi-cycle operations to complete within the arithmetic unit.
- **Propagation:** It routes the results (or exceptions) to the standard Fife Retire stage.

### Inter-Stage Pipeline Interfaces
The **`Inter_Stage.bsv`** definitions were expanded to establish the newly required FIFO connections for the Posit pipeline.
- We added `f_RR_to_EX_Posit` to carry operands from the Register-Read (RR) stage.
- We added `f_EX_Posit_to_Retire` to carry the write-back results to the retirement queue.

### Instruction Decoding & Dispatch
To allow the CPU to recognize posit instructions, we updated **`Fn_Decode.bsv`** and created **`Posit_Instr_Bits.bsv`**.
- **Custom-0 Opcode:** The decoder was programmed to identify the standard RISC-V `custom-0` opcode (`0x0B`).
- **Hazard Detection:** We configured the decoder to accurately extract the read and write dependencies (`has_rd`, `has_rs1`, `has_rs2`) from these custom instructions, allowing the core's Scoreboard to properly manage data hazards.
- **Dispatching:** **`Fn_Dispatch.bsv`** was modified to route these decoded custom-0 instructions directly to `S4_EX_Posit` instead of the standard ALU.

---

## 2. Source Code Migration & Version Control

To cleanly maintain the two repositories, we established integration branches:
- **`fife-integration` (Melodica):** We migrated the modified Melodica sources from our temporary workspace into the forked Melodica repository.
- **`fife-melodica-integration` (Fife):** We placed the wrapper modules and modified Fife files into `Code/src_Fife/`.

By keeping the repositories distinct but linked within the same workspace, we ensured that both could be managed and updated independently in the future.

---

## 3. Build System and Compiler Configuration

Integrating two independent Bluespec codebases required synchronizing the Fife compilation environment to resolve Melodica dependencies.

### Dynamic Path Linking
We updated the Fife Makefile at **`Code/Build/Include.mk`**:
- Defined `MELODICA_SRC` to point dynamically to the sibling `Melodica/src_bsv/` repository.
- Expanded the `BSCPATH` array to include all essential PositCore subdirectories:
  - `$(MELODICA_SRC)`
  - `$(MELODICA_SRC)/Fused_Op`
  - `$(MELODICA_SRC)/lib`
  - `$(MELODICA_SRC)/Multiplier`
  - `$(MELODICA_SRC)/Posit_Divider`

### Standalone Macro
The original `PositCore.bsv` contained dependencies on floating-point libraries (`FPU_Types`) that do not exist within the Fife core. To safely bypass this missing dependency, we injected the `-D STANDALONE` flag into `BSCFLAGS` during compilation. This preprocessor macro commands the compiler to omit the problematic `import` statement inside `PositCore`, successfully bridging the environments.

---

## 4. Building the Project

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

## 5. Running Test Programs

We have written assembly test programs specifically to test posit arithmetic. They are located in `src_Fife/test_programs/`:

- **`posit_basic.S`**: Tests basic posit initialization and register file writes. It verifies that posit registers can be loaded properly.
- **`posit_convert.S`**: Tests precision conversions. Includes `pcvtp` (float to posit) and `pcvtf` (posit to float) instructions, testing edge cases like zero, infinity, and NaN conversions between formats.
- **`posit_dot_product.S`**: Tests complex operations utilizing the Quire for zero-loss vector dot products. It utilizes `pfma` (Posit Fused Multiply-Accumulate) to accumulate results into the quire, followed by `prdq` (Posit Read Quire) to extract the final dot product result back to standard registers.

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

## 6. Synthesizing Hardware and Extracting Critical Path

Once the Bluespec compiler (`bsc`) has generated the verilog outputs during the build step, you can synthesize the hardware netlist and extract the critical path length using **Yosys**.

1. Navigate to the Verilog output directory:
```bash
cd /teamspace/studios/this_studio/Learn_Bluespec_and_RISCV_Design/Code/Build/Fife/verilog/
```

2. Run Yosys with the provided synthesis script:
```bash
# We pipe the output to filter out the combinatorial loop warnings generated by ltp
yosys synth.ys 2>&1 | grep -v "Warning: Detected loop at" > synth.log
```
*Note: The `synth.ys` script reads the verilog modules, executes the `synth -top mkCPU` pass to map logic, and then runs the `ltp` (Longest Topological Path) command to find the critical path.*

3. Extract the critical path:
```bash
# This searches for the start of the ltp output block for mkCPU
awk '/Longest topological path in mkCPU/{flag=1} flag; /^$/{if(flag) flag=0}' synth.log
```
This will print the steps of the critical path and the total logic levels (length). In standard builds, the critical path resides in the control logic (FSM and pipeline CAN_FIRE/WILL_FIRE handshaking) rather than the Posit arithmetic datapath itself.

---

## 7. Forwarding vs Baseline Performance Comparison

To evaluate the impact of the newly integrated EX-to-RR integer forwarding logic, we ran a suite of benchmarks comparing the **Baseline Design** against the **Forwarding Design**.

### Cycle & IPC Improvements
By bypassing RAW (Read-After-Write) hazards, the forwarding logic dramatically reduces pipeline stalls for data-dependent integer instructions.

![IPC Comparison](./docs/images/ipc_comparison.png)
![Stall Rate Comparison](./docs/images/stall_rate_comparison.png)

Key benchmark highlights:
- **`raw_int_chain`**: IPC increased from ~0.26 to **0.44**. Stall rate dropped from ~66% to **34%**.
- **`raw_worst_case`**: IPC increased from ~0.20 to **0.31**. Stalls were drastically reduced, leaving only necessary WAW (Write-After-Write) stalls managed by our 4-bit scoreboard counter.
- **`posit_dot_product`**: IPC remained roughly equivalent (~0.29). As expected, forwarding does not improve multi-cycle Posit operations, which are intrinsically bottlenecked by the PositCore throughput rather than integer RAW hazards.

### Hardware Synthesis Trade-offs (Critical Path)
Adding forwarding multiplexers and complex scoreboard counters to the pipeline comes at a slight hardware cost in terms of combinatorial logic depth. We synthesized both designs using `Yosys` to compare the Longest Topological Path (LTP).

| Module | Baseline (Logic Levels) | Forwarding (Logic Levels) | Impact |
| :--- | :--- | :--- | :--- |
| **`mkRR_WB`** (Register Read) | 56 | 73 | +30% |
| **`mkCPU`** (Global Top) | 1727 | 1727 | No change |
| **`mkQuire`** (Posit Accumulator)| 3218 | 3218 | No change |

**Expected Clock Speed Conclusion:**
While the `mkRR_WB` (Register Read / Writeback) stage saw a 30% increase in logic levels due to the new bypass multiplexers and WAW tracking, the **overall expected clock speed of the processor remains unchanged**. This is because the global critical path of the processor is heavily dominated by the 512-bit `mkQuire` adder logic (3218 levels), which shadows the control logic delays in the pipeline stages.

Therefore, the forwarding logic provides a "free" IPC boost for integer workloads without penalizing the final achievable clock frequency of the Melodica-integrated Fife Core!
