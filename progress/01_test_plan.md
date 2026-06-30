# 01 – Test Plan

## Existing Tests (from repository)

| Test | File | Tests |
|------|------|-------|
| posit_basic | posit_basic.S | Posit register load/store |
| posit_convert | posit_convert.S | pcvtp, pcvtf edge cases |
| posit_dot_product | posit_dot_product.S | pfma × 4, prdq, quire accumulation |

## New RAW Hazard Tests (to be created)

| Test | File | Hazard type |
|------|------|-------------|
| raw_int_single | raw_int_single.S | Single RAW: ADD x1,x0,x0 → ADDI x2,x1,1 |
| raw_int_chain | raw_int_chain.S | Chain of 5 dependent ADDs |
| raw_int_backtoback | raw_int_backtoback.S | 10 back-to-back ADDI→ADD dependent pairs |
| raw_int_loop | raw_int_loop.S | Loop-carried RAW: s0 += s1 per iteration (100 iters) |
| raw_worst_case | raw_worst_case.S | Every instr reads previous rd (max stalls) |
| raw_posit_chain | raw_posit_chain.S | Integer → Posit (uses pcvtp) → Integer (uses pcvtf result) |
| raw_mixed | raw_mixed.S | Interleaved integer and posit with data dependencies |

## Metrics to Collect

The Verilator simulation produces a `log.txt` when run with `+log`.
We will parse this to extract:

1. **Total cycles** – from simulation start to `GPIO tohost PASS`
2. **Instructions retired** – count of `RET.*` trace lines in log
3. **Stall cycles** – count of `RR.S` trace lines in log
4. **IPC** = instructions / cycles
5. **Stall rate** = stall_cycles / (stall_cycles + instructions_retired)

## Benchmark Automation

Script: `progress/run_benchmarks.sh`
- Symlinks test.memhex32, runs simulation with +log, parses output.
- Produces a summary CSV: `progress/benchmark_results.csv`

## Synthesis / Timing

Run Yosys with `synth.ys` on the verilog/ directory.
Parse `ltp` output to get:
- Critical path length (in logic levels / gate depths)
- Path start/end nodes
