# 00 – Initial Architecture Analysis

## Pipeline Stages

The Fife core is a 5-stage (effectively 6-stage) in-order pipeline:

| # | Stage name | File | Key function |
|---|-----------|------|--------------|
| S1 | Fetch | `S1_Fetch.bsv` | Send PC to IMem; receive redirects from Retire |
| S2 | Decode | `S2_Decode.bsv` | Receive IMem response; decode instr to Decode_to_RR packet |
| S3 | Register-Read + Dispatch | `S3_RR_S6_WB.bsv` | Scoreboard check; read GPRs; dispatch to EX units |
| S4a | EX_Control | `S4_EX_Control.bsv` | 1-cycle: Branch/JAL/JALR resolution |
| S4b | EX_Int | `S4_EX_Int.bsv` | 1-cycle: ALU (LUI,AUIPC,ADDI,ADD,…) |
| S4c | EX_Posit | `S4_EX_Posit.bsv` | Multi-cycle: Posit arith via Melodica PositCore |
| S5 | Retire | `S5_Retire.bsv` | In-order commit; write-back; redirect Fetch |
| S6 | Write-Back | (inside S3) | GPR write triggered by fi_RW_from_Retire from Retire |

Note: S6 (write-back) shares the S3 module.  The `rl_RW_from_Retire` rule
clears the scoreboard and writes the GPR from within `mkRR_WB`.

## Operand Read Location

Operands (rs1_val, rs2_val) are read in **S3 (Register-Read)**:
- `gprs.read_rs1(rs1)` and `gprs.read_rs2(rs2)` in `rl_RR_Dispatch`.
- The values are forwarded in the `RR_to_EX` packet to the EX stage.

## Where Results Become Available

| Pipeline path | Latency after dispatch | Where result appears |
|--------------|----------------------|---------------------|
| EX_Int | 1 clock cycle | `f_EX_Int_to_Retire` (BypassFIFO output) |
| EX_Control | 1 clock cycle | `f_EX_Control_to_Retire` (BypassFIFO output) |
| EX_Posit | 3–12 cycles (op-dependent) | `f_EX_Posit_to_Retire` |

After Retire processes the result, it sends `RW_from_Retire` → S3 writes back
the GPR and clears the scoreboard.  The write-back takes at minimum 2 cycles
after the EX result is available (Retire + write-back pipeline stage).

## Scoreboard Operation

In `S3_RR_S6_WB.bsv`:
```
rg_scoreboard: Reg #(Scoreboard)   // Scoreboard = Vector #(32, Bit #(1))

// In rl_RR_Dispatch:
busy_rs1 = (has_rs1 && scoreboard[rs1] != 0)
busy_rs2 = (has_rs2 && scoreboard[rs2] != 0)
busy_rd  = (has_rd  && scoreboard[rd]  != 0)
stall    = busy_rs1 || busy_rs2 || busy_rd

// If not stalling:
scoreboard[rd] = 1   // mark rd busy

// In rl_RW_from_Retire:
scoreboard[x.rd] = 0  // clear when Retire writes back
gprs.write_rd(x.rd, x.data)
```

**Key observation**: rd is also checked for busyness.  This prevents WAW (Write-After-Write)
and WAR hazards in addition to RAW.  But for a simple in-order pipeline, WAW/WAR cannot
naturally occur — this is conservative but safe.

## RAW Hazards That Currently Cause Stalls

For an integer instruction I2 that reads a register written by I1:

```
Cycle N:   I1 dispatched from S3  → scoreboard[rd1] = 1
Cycle N+1: I1 result in EX_Int_to_Retire (BypassFIFO)
           I2 at S3: sees scoreboard[rd1]=1  → STALL
Cycle N+2: Retire processes I1, sends RW_from_Retire
           I2 still stalling (scoreboard not yet cleared)
Cycle N+3: rl_RW_from_Retire fires: scoreboard[rd1] = 0; GPR updated
           I2 at S3: scoreboard[rd1]=0 → dispatches with CORRECT value
```

This means an INT→INT RAW hazard causes **2 stall cycles** even though the
result is available 1 cycle after dispatch.

For a Posit instruction I1 with rd (e.g. prdq, 4-cycle latency):
```
Cycle N:   I1 dispatched → scoreboard[rd1] = 1
Cycles N+1 to N+4: PositCore computing
Cycle N+4: EX_Posit result ready
Cycle N+5: Retire processes → sends RW_from_Retire
Cycle N+6: Scoreboard cleared; GPR written
```
→ Posit-result RAW causes **5–14 stall cycles** depending on operation.

## Forwarding Opportunities

### INT → INT (eliminates 2 stalls)
Forward the EX_Int result (available cycle N+1) directly into the RR stage
so the dependent instruction I2 can read it without waiting for write-back.

Implementation: On each cycle, maintain a "forwarding register" holding the
last EX_Int result (rd_tag, rd_val, valid).  In rl_RR_Dispatch, if rs1 or rs2
matches the forwarding register tag, bypass the GPR read.

Also clear the scoreboard for the forwarded instruction immediately (since the
result is now available), rather than waiting for Retire.

### WB → RR (eliminates 1 stall — already in GPRs_b.bsv)
When a write-back arrives the same cycle as a new dispatch, the GPRs_b module
forwards the write-back data directly to rs1_val/rs2_val.

### What Cannot Be Forwarded
- **Posit results (prdq, pcvtp, pcvtf)**: The PositCore is multi-cycle.
  The result is not available until EX_Posit produces its output, which is
  after the S3 stage has already stalled many cycles.  These stalls cannot
  be reduced without making PositCore pipelined (a much larger change).
- **Load-use hazards**: After a LOAD, data arrives from DMem 1–2 cycles after
  dispatch.  Forwarding from DMem response → RR would require a separate
  forwarding path.  This is lower priority since LOAD is uncommon in tight loops.

## Existing Bypass Infrastructure

- `S3_RR_S6_WB_bypassed.bsv` exists but is **commented out** in `CPU.bsv` (line 40).
- `GPRs_b.bsv` implements the WB→RR bypass, but:
  - Still uses the full scoreboard (stalls until WB arrives, not until EX result is ready).
  - **Missing**: `fo_RR_to_EX_Posit` interface — cannot dispatch Posit instructions.
- The full EX→RR integer bypass (1-cycle result) is **not yet implemented**.

## Conclusion

The most impactful optimization for integer-heavy code is **EX_Int→RR forwarding**,
which eliminates 2 stall cycles per INT→INT RAW hazard.  For Posit-heavy code,
forwarding provides minimal benefit since the bottleneck is the multi-cycle Posit unit.
