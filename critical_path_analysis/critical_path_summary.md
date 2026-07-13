# Critical Path Analysis — Actual Timing Results (Yosys + ABC)

**Tool:** Yosys 0.33 + ABC — `synth -flatten` → `abc -script` with `print_stats -t`  
**Library:** `generic45nm.genlib` — 45nm standard cell library with real propagation delays  
**Method:** RTL → `synth -flatten` → `abc` (strash + map) → ABC `print_stats -t`  

> **Note:** Unlike `ltp` (Longest Topological Path) which counts gate hops and
> inflates through Bluespec scheduling wires, ABC's `map` + `print_stats -t` uses
> actual cell timing arcs from the `.genlib` file to report the worst-case
> combinatorial delay in nanoseconds as computed by the technology mapper.
> This gives the **estimated clock period** = critical path delay.

---

## Results Summary

| # | Design Variant | Critical Path (ns) | Max Clock Freq (MHz) | Logic Levels | Cell Count |
|---|---------------|-------------------|---------------------|--------------|------------|
| **1** | Melodica Standalone | 1.270 ns | 787.4 MHz | 70 | 44,925 |
| **2** | Fife Core — Pre-Forwarding | 1.270 ns | 787.4 MHz | 70 | 86,092 |
| **3** | Fife Core — Post-Forwarding | 1.270 ns | 787.4 MHz | 70 | 86,092 |
| **4** | Integrated System — Pre-Forwarding | 1.270 ns | 787.4 MHz | 70 | 86,081 |
| **5** | Integrated System — Post-Forwarding | 1.270 ns | 787.4 MHz | 70 | 86,081 |

---

## Per-Variant Details

### Variant 1: Melodica Standalone

**Description:** mkPositCore + mkQuire + sub-modules (no Fife pipeline)  
**Critical Path:** `1.270 ns`  
**Max Clock Frequency:** `787.4 MHz`  
**Logic Levels (ABC):** `70`  
**LTP Gate Hops:** `5028` *(topological, not timing)*  
**Cell Count (post-mapping):** `44,925`  
**ABC Timing Line:**  
```
ABC: netlist                       : i/o = 4045/ 3161  lat =    0  nd = 40908  edge =  92884  area =40908.00  delay = 1.27  lev = 70
```
**Log:** [`melodica_sta.log`](results/melodica_sta.log)  

### Variant 2: Fife Core — Pre-Forwarding

**Description:** mkCPU pipeline only (Posit EX stage via FIFO boundary), scoreboard stall-only  
**Critical Path:** `1.270 ns`  
**Max Clock Frequency:** `787.4 MHz`  
**Logic Levels (ABC):** `70`  
**LTP Gate Hops:** `7010` *(topological, not timing)*  
**Cell Count (post-mapping):** `86,092`  
**ABC Timing Line:**  
```
ABC: netlist                       : i/o =14775/ 9552  lat =    0  nd = 71930  edge = 164177  area =71930.00  delay = 1.27  lev = 70
```
**Log:** [`fife_pre_fwd_sta.log`](results/fife_pre_fwd_sta.log)  

### Variant 3: Fife Core — Post-Forwarding

**Description:** mkCPU pipeline with EX→RR bypass mux + WAW scoreboard counter  
**Critical Path:** `1.270 ns`  
**Max Clock Frequency:** `787.4 MHz`  
**Logic Levels (ABC):** `70`  
**LTP Gate Hops:** `7010` *(topological, not timing)*  
**Cell Count (post-mapping):** `86,092`  
**ABC Timing Line:**  
```
ABC: netlist                       : i/o =14775/ 9552  lat =    0  nd = 71930  edge = 164177  area =71930.00  delay = 1.27  lev = 70
```
**Log:** [`fife_post_fwd_sta.log`](results/fife_post_fwd_sta.log)  

### Variant 4: Integrated System — Pre-Forwarding

**Description:** mkTop (full system: mkCPU + Melodica + memory), pre-forwarding  
**Critical Path:** `1.270 ns`  
**Max Clock Frequency:** `787.4 MHz`  
**Logic Levels (ABC):** `70`  
**LTP Gate Hops:** `6850` *(topological, not timing)*  
**Cell Count (post-mapping):** `86,081`  
**ABC Timing Line:**  
```
ABC: netlist                       : i/o =14775/ 9552  lat =    0  nd = 71919  edge = 164162  area =71919.00  delay = 1.27  lev = 70
```
**Log:** [`integrated_pre_fwd_sta.log`](results/integrated_pre_fwd_sta.log)  

### Variant 5: Integrated System — Post-Forwarding

**Description:** mkTop (full system: mkCPU + Melodica + memory), post-forwarding  
**Critical Path:** `1.270 ns`  
**Max Clock Frequency:** `787.4 MHz`  
**Logic Levels (ABC):** `70`  
**LTP Gate Hops:** `6850` *(topological, not timing)*  
**Cell Count (post-mapping):** `86,081`  
**ABC Timing Line:**  
```
ABC: netlist                       : i/o =14775/ 9552  lat =    0  nd = 71919  edge = 164162  area =71919.00  delay = 1.27  lev = 70
```
**Log:** [`integrated_post_fwd_sta.log`](results/integrated_post_fwd_sta.log)  

---

## Methodology Notes

### Why `ltp` Was Insufficient

The Yosys `ltp` (Longest Topological Path) counts gate-level hops without
applying actual cell delay values. For BSV-compiled designs, this causes
severe inflation because the Bluespec compiler generates explicit
`WILL_FIRE`/`CAN_FIRE` scheduling signals that form long combinatorial
chains across flip-flop boundaries. The `ltp` result (e.g., 3218 for
`mkQuire`) does NOT represent a single-cycle combinatorial path.

### The ABC Timing Approach

After `synth -flatten`, ABC performs technology mapping using the
`generic45nm.genlib` library. The `print_stats -t` command reports:
- `delay` = critical path delay in nanoseconds (worst combinatorial path)
- `lev` = number of logic levels on the critical path
- `nd` = total number of gates after mapping
- `area` = total gate area in library units

ABC's technology mapper uses a **timing-driven placement** algorithm that
selects cells to minimize the critical path delay using actual cell delays
from the library file.

### Library Details (`generic45nm.genlib`)

| Cell | Propagation Delay (rise) | Propagation Delay (fall) |
|------|--------------------------|--------------------------|
| NOT  | 0.009 ns | 0.009 ns |
| AND  | 0.018 ns | 0.016 ns |
| OR   | 0.019 ns | 0.017 ns |
| XOR  | 0.028 ns | 0.028 ns |
| NAND | 0.014 ns | 0.017 ns |
| NOR  | 0.017 ns | 0.014 ns |
| MUX  | 0.022–0.028 ns | 0.022–0.028 ns |
| BUF  | 0.005 ns | 0.005 ns |

