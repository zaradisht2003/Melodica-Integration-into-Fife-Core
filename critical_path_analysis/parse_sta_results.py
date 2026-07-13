#!/usr/bin/env python3
"""
parse_sta_results.py
Parses Yosys+ABC synthesis output logs to extract:
  - Critical path delay (ns) from ABC's print_stats -t output
  - Maximum achievable clock frequency (MHz)
  - Logic levels (gate hops on critical path)
  - Cell count after technology mapping

ABC print_stats -t format:
  netlist : i/o = XX/YY  lat = N  nd = GG  edge = EE  area = A.AA  delay = D.DD  lev = L

Usage:
    python3 parse_sta_results.py  (run from critical_path_analysis/ directory)
"""

import re
import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results")

VARIANTS = [
    {
        "id": 1,
        "name": "Melodica Standalone",
        "desc": "mkPositCore + mkQuire + sub-modules (no Fife pipeline)",
        "log": "melodica_sta.log",
    },
    {
        "id": 2,
        "name": "Fife Core — Pre-Forwarding",
        "desc": "mkCPU pipeline only (Posit EX stage via FIFO boundary), scoreboard stall-only",
        "log": "fife_pre_fwd_sta.log",
    },
    {
        "id": 3,
        "name": "Fife Core — Post-Forwarding",
        "desc": "mkCPU pipeline with EX→RR bypass mux + WAW scoreboard counter",
        "log": "fife_post_fwd_sta.log",
    },
    {
        "id": 4,
        "name": "Integrated System — Pre-Forwarding",
        "desc": "mkTop (full system: mkCPU + Melodica + memory), pre-forwarding",
        "log": "integrated_pre_fwd_sta.log",
    },
    {
        "id": 5,
        "name": "Integrated System — Post-Forwarding",
        "desc": "mkTop (full system: mkCPU + Melodica + memory), post-forwarding",
        "log": "integrated_post_fwd_sta.log",
    },
]


def parse_log(log_path):
    """Parse a Yosys+ABC synthesis log and return timing metrics.
    
    ABC print_stats -t produces a line like:
      netlist : i/o = 16/ 8  lat = 0  nd = 40  edge = 80  area = 40.00  delay = 0.18  lev = 10
    """
    result = {
        "critical_path_ns": None,
        "max_freq_mhz": None,
        "logic_levels": None,
        "cell_count": None,
        "gate_count_abc": None,  # ABC nd= (gate count)
        "area_abc": None,        # ABC area=
        "ltp_length": None,      # ltp pass gate hops
        "error": None,
        "raw_abc_stats": [],
    }

    if not os.path.exists(log_path):
        result["error"] = f"Log file not found: {log_path}"
        return result

    with open(log_path, "r") as f:
        lines = f.readlines()

    # Parse ABC print_stats -t output line
    # Format: "ABC: netlist : i/o = XX/YY  lat = N  nd = GG  edge = EE  area = A.AA  delay = D.DD  lev = L"
    abc_stats_lines = []
    for line in lines:
        if "ABC:" in line and "netlist" in line and "delay" in line:
            abc_stats_lines.append(line.strip())

    result["raw_abc_stats"] = abc_stats_lines

    # Extract timing from the LAST abc stats line (after optimization passes)
    for line in reversed(abc_stats_lines):
        # Parse delay
        m = re.search(r'\bdelay\s*=\s*(\d+\.?\d*)', line)
        if m:
            result["critical_path_ns"] = float(m.group(1))

        # Parse logic levels
        m = re.search(r'\blev\s*=\s*(\d+)', line)
        if m:
            result["logic_levels"] = int(m.group(1))

        # Parse gate count (nd)
        m = re.search(r'\bnd\s*=\s*(\d+)', line)
        if m:
            result["gate_count_abc"] = int(m.group(1))

        # Parse area
        m = re.search(r'\barea\s*=\s*(\d+\.?\d*)', line)
        if m:
            result["area_abc"] = float(m.group(1))

        if result["critical_path_ns"] is not None:
            break

    # Fallback: also look for older Yosys sta pass output format
    if result["critical_path_ns"] is None:
        for line in lines:
            # Pattern: "Longest topological path in <module> (length=N)"
            m = re.search(r'Longest topological path.*?([\d.]+)\s*ns', line)
            if m:
                result["critical_path_ns"] = float(m.group(1))
                break

            # Pattern: "Critical path delay: X.XXX ns"
            m = re.search(r'Critical path delay[:\s]+([\d.]+)\s*ns', line, re.IGNORECASE)
            if m:
                result["critical_path_ns"] = float(m.group(1))
                break

    # Parse LTP pass output (gate hops — informational only)
    for line in lines:
        # "Longest topological path in <module> (length=N):"
        m = re.search(r'Longest topological path.*?length=(\d+)', line)
        if m:
            result["ltp_length"] = int(m.group(1))
            break

    # Parse cell count from stat output
    for line in lines:
        m = re.search(r'Number of cells:\s+(\d+)', line)
        if m:
            result["cell_count"] = int(m.group(1))

    # Calculate max frequency
    if result["critical_path_ns"] and result["critical_path_ns"] > 0:
        result["max_freq_mhz"] = round(1000.0 / result["critical_path_ns"], 2)

    # Check for errors
    for line in lines:
        if "ERROR:" in line:
            result["error"] = line.strip()
            break

    return result


def format_ns(val):
    if val is None:
        return "N/A"
    return f"{val:.3f} ns"


def format_mhz(val):
    if val is None:
        return "N/A"
    return f"{val:.1f} MHz"


def format_cells(val):
    if val is None:
        return "N/A"
    return f"{val:,}"


def format_int(val):
    if val is None:
        return "N/A"
    return str(val)


def print_abc_stats(stats_lines, max_lines=5):
    """Print the ABC stats lines for debugging."""
    print("  [ABC Timing Output]")
    for line in stats_lines[:max_lines]:
        print("   ", line)


def main():
    print("=" * 80)
    print("CRITICAL PATH ANALYSIS RESULTS — Yosys+ABC with generic45nm.genlib")
    print("=" * 80)
    print()

    results = []
    for variant in VARIANTS:
        log_path = os.path.join(RESULTS_DIR, variant["log"])
        r = parse_log(log_path)
        r.update(variant)
        results.append(r)

        status = "✓" if r["critical_path_ns"] else "✗"
        print(f"[{status}] Variant {variant['id']}: {variant['name']}")
        if r["error"]:
            print(f"    ERROR: {r['error']}")
        elif r["critical_path_ns"]:
            print(f"    Critical Path: {format_ns(r['critical_path_ns'])}  |  Max Freq: {format_mhz(r['max_freq_mhz'])}")
            print(f"    Logic Levels: {format_int(r['logic_levels'])}  |  Cells: {format_cells(r['cell_count'])}  |  LTP hops: {format_int(r['ltp_length'])}")
            if r["raw_abc_stats"]:
                print_abc_stats(r["raw_abc_stats"])
        else:
            print(f"    WARNING: Could not parse timing — check {log_path}")
            if r["raw_abc_stats"]:
                print_abc_stats(r["raw_abc_stats"])
        print()

    # Print comparison table
    print()
    print("=" * 88)
    print("COMPARISON TABLE")
    print("=" * 88)
    print()
    header = f"{'#':<3} {'Design Variant':<40} {'Critical Path':>15} {'Max Freq':>12} {'Levels':>8} {'Cells':>10}"
    print(header)
    print("-" * 90)
    for r in results:
        row = (
            f"{r['id']:<3} "
            f"{r['name']:<40} "
            f"{format_ns(r['critical_path_ns']):>15} "
            f"{format_mhz(r['max_freq_mhz']):>12} "
            f"{format_int(r['logic_levels']):>8} "
            f"{format_cells(r['cell_count']):>10}"
        )
        print(row)
    print("-" * 90)
    print()

    # Write markdown summary
    write_markdown_summary(results)
    print(f"Markdown summary written to: critical_path_analysis/critical_path_summary.md")


def write_markdown_summary(results):
    """Write a formatted markdown summary of results."""
    summary_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "critical_path_summary.md"
    )

    with open(summary_path, "w") as f:
        f.write("# Critical Path Analysis — Actual Timing Results (Yosys + ABC)\n\n")
        f.write("**Tool:** Yosys 0.33 + ABC — `synth -flatten` → `abc -script` with `print_stats -t`  \n")
        f.write("**Library:** `generic45nm.genlib` — 45nm standard cell library with real propagation delays  \n")
        f.write("**Method:** RTL → `synth -flatten` → `abc` (strash + map) → ABC `print_stats -t`  \n\n")
        f.write("> **Note:** Unlike `ltp` (Longest Topological Path) which counts gate hops and\n")
        f.write("> inflates through Bluespec scheduling wires, ABC's `map` + `print_stats -t` uses\n")
        f.write("> actual cell timing arcs from the `.genlib` file to report the worst-case\n")
        f.write("> combinatorial delay in nanoseconds as computed by the technology mapper.\n")
        f.write("> This gives the **estimated clock period** = critical path delay.\n\n")
        f.write("---\n\n")

        f.write("## Results Summary\n\n")
        f.write("| # | Design Variant | Critical Path (ns) | Max Clock Freq (MHz) | Logic Levels | Cell Count |\n")
        f.write("|---|---------------|-------------------|---------------------|--------------|------------|\n")
        for r in results:
            cp = format_ns(r["critical_path_ns"])
            freq = format_mhz(r["max_freq_mhz"])
            levels = format_int(r["logic_levels"])
            cells = format_cells(r["cell_count"])
            note = " ⚠️ ERROR" if r.get("error") else ""
            f.write(f"| **{r['id']}** | {r['name']}{note} | {cp} | {freq} | {levels} | {cells} |\n")

        f.write("\n---\n\n")
        f.write("## Per-Variant Details\n\n")
        for r in results:
            f.write(f"### Variant {r['id']}: {r['name']}\n\n")
            f.write(f"**Description:** {r['desc']}  \n")
            if r.get("error"):
                f.write(f"**Status:** ❌ Error: `{r['error']}`  \n\n")
            else:
                f.write(f"**Critical Path:** `{format_ns(r['critical_path_ns'])}`  \n")
                f.write(f"**Max Clock Frequency:** `{format_mhz(r['max_freq_mhz'])}`  \n")
                f.write(f"**Logic Levels (ABC):** `{format_int(r['logic_levels'])}`  \n")
                f.write(f"**LTP Gate Hops:** `{format_int(r['ltp_length'])}` *(topological, not timing)*  \n")
                f.write(f"**Cell Count (post-mapping):** `{format_cells(r['cell_count'])}`  \n")
                if r.get("raw_abc_stats"):
                    f.write(f"**ABC Timing Line:**  \n")
                    for line in r["raw_abc_stats"][:1]:
                        f.write(f"```\n{line}\n```\n")
            f.write(f"**Log:** [`{r['log']}`](results/{r['log']})  \n\n")

        f.write("---\n\n")
        f.write("## Methodology Notes\n\n")
        f.write("### Why `ltp` Was Insufficient\n\n")
        f.write("The Yosys `ltp` (Longest Topological Path) counts gate-level hops without\n")
        f.write("applying actual cell delay values. For BSV-compiled designs, this causes\n")
        f.write("severe inflation because the Bluespec compiler generates explicit\n")
        f.write("`WILL_FIRE`/`CAN_FIRE` scheduling signals that form long combinatorial\n")
        f.write("chains across flip-flop boundaries. The `ltp` result (e.g., 3218 for\n")
        f.write("`mkQuire`) does NOT represent a single-cycle combinatorial path.\n\n")
        f.write("### The ABC Timing Approach\n\n")
        f.write("After `synth -flatten`, ABC performs technology mapping using the\n")
        f.write("`generic45nm.genlib` library. The `print_stats -t` command reports:\n")
        f.write("- `delay` = critical path delay in nanoseconds (worst combinatorial path)\n")
        f.write("- `lev` = number of logic levels on the critical path\n")
        f.write("- `nd` = total number of gates after mapping\n")
        f.write("- `area` = total gate area in library units\n\n")
        f.write("ABC's technology mapper uses a **timing-driven placement** algorithm that\n")
        f.write("selects cells to minimize the critical path delay using actual cell delays\n")
        f.write("from the library file.\n\n")
        f.write("### Library Details (`generic45nm.genlib`)\n\n")
        f.write("| Cell | Propagation Delay (rise) | Propagation Delay (fall) |\n")
        f.write("|------|--------------------------|--------------------------|\n")
        f.write("| NOT  | 0.009 ns | 0.009 ns |\n")
        f.write("| AND  | 0.018 ns | 0.016 ns |\n")
        f.write("| OR   | 0.019 ns | 0.017 ns |\n")
        f.write("| XOR  | 0.028 ns | 0.028 ns |\n")
        f.write("| NAND | 0.014 ns | 0.017 ns |\n")
        f.write("| NOR  | 0.017 ns | 0.014 ns |\n")
        f.write("| MUX  | 0.022–0.028 ns | 0.022–0.028 ns |\n")
        f.write("| BUF  | 0.005 ns | 0.005 ns |\n\n")


if __name__ == "__main__":
    main()
