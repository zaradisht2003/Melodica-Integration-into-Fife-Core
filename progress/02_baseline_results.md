# 02 – Baseline Results

## All Tests: PASS

| Test | Retired Instrs | Stall Cycles | Active Cycles | IPC | Stall % |
|------|---------------|-------------|--------------|-----|---------|
| posit_basic | 24 | 81 | 129 | 0.1860 | 77.1% |
| posit_convert | 30 | 59 | 114 | 0.2632 | 66.3% |
| posit_dot_product | 87 | 142 | 305 | 0.2852 | 62.0% |
| raw_int_single | 25 | 16 | 56 | 0.4464 | 39.0% |
| raw_int_chain | 30 | 33 | 85 | 0.3529 | 52.4% |
| raw_int_backtoback | 39 | 51 | 121 | 0.3223 | 56.7% |
| raw_int_loop | 583 | 252 | 1247 | 0.4675 | 30.2% |
| raw_worst_case | 56 | 85 | 189 | 0.2963 | 60.3% |
| raw_posit_chain | 19 | 38 | 78 | 0.2436 | 66.7% |
| raw_mixed | 34 | 59 | 129 | 0.2636 | 63.4% |

**Average IPC (integer tests):** 0.381  
**Average stall rate (integer tests):** 47.7%

**Average IPC (posit tests):** 0.258  
**Average stall rate (posit tests):** 68.5%

## Key Observations

1. **Posit tests have very high stall rates (62–77%)** due to multi-cycle posit operations.
   Forwarding cannot help these stalls (cannot bypass a 3–12 cycle computation).

2. **Integer RAW tests have moderate stall rates (30–60%)** due to 2-cycle scoreboard stalls.
   These are the primary target for EX→RR forwarding.

3. **raw_worst_case (60.3% stalls)**: Every instruction reads the previous result.
   This represents the maximum possible benefit from forwarding.

4. **raw_int_loop (30.2% stalls)**: Loop-carried RAW (ADD x, x, y per iteration).
   The loop overhead (branch, decrement) reduces the stall fraction.

5. **raw_posit_chain (66.7% stalls)**: Waiting for posit results to feed integer ops.
   Most stalls are from posit latency, not integer RAW.

## Baseline Timing Analysis (Yosys ltp)

| Metric | Value |
|--------|-------|
| **Critical path (logic levels)** | **1335** |
| Path start | CLK (through FSM state register) |
| Path end | `stage_RR_WB.EN_fi_RW_from_Retire_enq` |
| Key path components | Posit state machine → Retire readiness → RR WB enable |

The 1335-level path goes through the Posit state machine (complex FSM) through
Retire's EX-unit-valid logic back to the RR writeback enable.
This is NOT on the forwarding critical path, so forwarding additions should not
significantly lengthen the critical path.

## Forwarding Cycle Count Predictions (Baseline → Forwarding)

For each integer RAW stall, forwarding eliminates 2 cycles.
For each instruction reading a forwarded value, 0 stalls instead of 2.

| Test | Current stalls | Expected stalls (fwd) | Cycles saved |
|------|---------------|----------------------|-------------|
| raw_int_single | 16 | ~0 (all are INT→INT RAW) | ~16 |
| raw_int_chain | 33 | ~0 | ~33 |
| raw_int_backtoback | 51 | ~0 | ~51 |
| raw_int_loop | 252 | ~50 (branch/decrement stalls remain) | ~200 |
| raw_worst_case | 85 | ~0 | ~85 |
| raw_posit_chain | 38 | ~10 (posit stalls remain) | ~28 |
| raw_mixed | 59 | ~15 (posit stalls remain) | ~44 |
