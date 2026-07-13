#!/usr/bin/env python3
"""
run_critical_path_analysis.py
=============================================================================
Master script for critical path analysis of all 5 design variants.

Flow per variant:
  1. Run Yosys: read_verilog + hierarchy + synth -flatten + write_blif
  2. Run yosys-abc: read_blif + read_library (genlib) + strash + map + print_stats
  3. Parse "delay = X.XX" from ABC print_stats output
  4. Calculate max frequency = 1000 / delay_ns MHz

This approach bypasses the Yosys-internal ABC crash by calling yosys-abc
directly on the BLIF file that Yosys writes.

Usage:
    python3 run_critical_path_analysis.py
    
Requires:
    - yosys (0.33+)
    - yosys-abc
    - BSC compiler at bsc/bin/bsc
    - All Verilog files in Learn_Bluespec_and_RISCV_Design/Code/Build/Fife/verilog/
=============================================================================
"""

import os
import sys
import re
import subprocess
import shutil
import textwrap
from pathlib import Path

# ─────────────────────────────────────────────────────────────────────────────
# Paths
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR   = Path(__file__).parent.resolve()
REPO_ROOT    = SCRIPT_DIR.parent
VERILOG_DIR  = REPO_ROOT / "Learn_Bluespec_and_RISCV_Design/Code/Build/Fife/verilog"
BSC_PRIM_DIR = REPO_ROOT / "bsc/lib/Verilog"
BSC_BIN      = REPO_ROOT / "bsc/bin/bsc"
FIFE_SUBMOD  = REPO_ROOT / "Learn_Bluespec_and_RISCV_Design"
MELODICA_SRC = REPO_ROOT / "Melodica/src_bsv"
GENLIB       = REPO_ROOT / "generic45nm.genlib"
LIBERTY      = REPO_ROOT / "generic45nm.lib"
RESULTS_DIR  = SCRIPT_DIR / "results"
BLIF_DIR     = SCRIPT_DIR / "blif_workdir"
PRE_FWD_DIR  = SCRIPT_DIR / "pre_fwd_verilog"
SUMMARY_MD   = SCRIPT_DIR / "critical_path_summary.md"

# BSC Primitives needed by the designs
BSC_PRIMS = [
    BSC_PRIM_DIR / "FIFO1.v",
    BSC_PRIM_DIR / "FIFO2.v",
    BSC_PRIM_DIR / "SizedFIFO.v",
    BSC_PRIM_DIR / "RegFile.v",
]

# Melodica-specific design files
MELODICA_FILES = [
    VERILOG_DIR / "module_fn_twosC_quire.v",
    VERILOG_DIR / "mkQuire.v",
    VERILOG_DIR / "mkMultiplier.v",
    VERILOG_DIR / "mkNormalizer.v",
    VERILOG_DIR / "mkExtracter.v",
    VERILOG_DIR / "mkFtoP_PNE.v",
    VERILOG_DIR / "mkPtoF_PNE.v",
    VERILOG_DIR / "mkPositCore.v",
]

# Fife-only design files (excluding Melodica)
FIFE_ONLY_FILES = [
    VERILOG_DIR / "mkGPRs_synth.v",
    VERILOG_DIR / "mkGPR_Logging_synth.v",
    VERILOG_DIR / "mkDecode.v",
    VERILOG_DIR / "mkFetch.v",
    VERILOG_DIR / "mkCSRs.v",
    VERILOG_DIR / "mkRetire.v",
    VERILOG_DIR / "mkEX_Control.v",
    VERILOG_DIR / "mkEX_Int.v",
    VERILOG_DIR / "mkEX_Posit.v",
    VERILOG_DIR / "mkRVFI_Report.v",
    VERILOG_DIR / "mkCPU.v",
]

# ─────────────────────────────────────────────────────────────────────────────
# Design Variants
# ─────────────────────────────────────────────────────────────────────────────
VARIANTS = [
    {
        "id": 1,
        "name": "Melodica Standalone",
        "desc": "mkPositCore + mkQuire + sub-modules (no Fife pipeline)",
        "top": "mkPositCore",
        "verilog_files": BSC_PRIMS + MELODICA_FILES,
        "blif": "melodica.blif",
        "log": "melodica_sta.log",
    },
    {
        "id": 2,
        "name": "Fife Core — Pre-Forwarding",
        "desc": "mkCPU pipeline, scoreboard stall-only (pre-forwarding mkRR_WB.v)",
        "top": "mkCPU",
        "verilog_files": BSC_PRIMS + MELODICA_FILES + FIFE_ONLY_FILES,
        "rr_wb_override": PRE_FWD_DIR / "mkRR_WB.v",  # pre-forwarding version
        "blif": "fife_pre_fwd.blif",
        "log": "fife_pre_fwd_sta.log",
    },
    {
        "id": 3,
        "name": "Fife Core — Post-Forwarding",
        "desc": "mkCPU pipeline with EX→RR bypass mux + WAW scoreboard counter",
        "top": "mkCPU",
        "verilog_files": BSC_PRIMS + MELODICA_FILES + FIFE_ONLY_FILES + [VERILOG_DIR / "mkRR_WB.v"],
        "blif": "fife_post_fwd.blif",
        "log": "fife_post_fwd_sta.log",
    },
    {
        "id": 4,
        "name": "Integrated System — Pre-Forwarding",
        "desc": "mkTop (full system: mkCPU + Melodica + memory), pre-forwarding",
        "top": "mkTop",
        "verilog_files": BSC_PRIMS + MELODICA_FILES + FIFE_ONLY_FILES + [VERILOG_DIR / "mkTop.v"],
        "rr_wb_override": PRE_FWD_DIR / "mkRR_WB.v",  # pre-forwarding version
        "blif": "integrated_pre_fwd.blif",
        "log": "integrated_pre_fwd_sta.log",
    },
    {
        "id": 5,
        "name": "Integrated System — Post-Forwarding",
        "desc": "mkTop (full system: mkCPU + Melodica + memory), post-forwarding",
        "top": "mkTop",
        "verilog_files": BSC_PRIMS + MELODICA_FILES + FIFE_ONLY_FILES + [
            VERILOG_DIR / "mkRR_WB.v", VERILOG_DIR / "mkTop.v"
        ],
        "blif": "integrated_post_fwd.blif",
        "log": "integrated_post_fwd_sta.log",
    },
]


# ─────────────────────────────────────────────────────────────────────────────
# Utilities
# ─────────────────────────────────────────────────────────────────────────────
RED    = "\033[0;31m"
GREEN  = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE   = "\033[0;34m"
BOLD   = "\033[1m"
NC     = "\033[0m"

def log(msg):   print(f"{BLUE}[INFO]{NC} {msg}")
def ok(msg):    print(f"{GREEN}[OK]{NC}   {msg}")
def warn(msg):  print(f"{YELLOW}[WARN]{NC} {msg}")
def err(msg):   print(f"{RED}[ERR]{NC}  {msg}")
def section(s): print(f"\n{BOLD}{'='*70}\n  {s}\n{'='*70}{NC}")


def run(cmd, cwd=None, capture=True, timeout=600):
    """Run a shell command, return (returncode, stdout+stderr)."""
    result = subprocess.run(
        cmd, shell=True, cwd=cwd,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=timeout
    )
    return result.returncode, result.stdout


def check_prereqs():
    """Verify required tools are present."""
    section("Checking Prerequisites")
    ok_flag = True
    for tool in ["yosys", "yosys-abc"]:
        path = shutil.which(tool)
        if path:
            rc, out = run(f"{tool} --version")
            version = out.strip().split("\n")[0]
            ok(f"{tool}: {version}")
        else:
            err(f"{tool} not found in PATH")
            ok_flag = False
    if not BSC_BIN.exists():
        warn(f"BSC not found at {BSC_BIN} — pre-forwarding recompile will be skipped")
    if not GENLIB.exists():
        err(f"generic45nm.genlib not found at {GENLIB}")
        ok_flag = False
    return ok_flag


def generate_pre_forwarding_mkrr_wb():
    """
    Extract pre-forwarding S3_RR_S6_WB.bsv from git and recompile to get mkRR_WB.v.
    Returns True if successful, False otherwise.
    """
    section("Generating Pre-Forwarding mkRR_WB.v")
    target = PRE_FWD_DIR / "mkRR_WB.v"
    PRE_FWD_DIR.mkdir(parents=True, exist_ok=True)

    if target.exists():
        ok(f"Pre-forwarding mkRR_WB.v already exists at {target}")
        return True

    PRE_FWD_COMMIT = "2aa5711"  # "Integrate posit arithmetic from Melodica" — no forwarding
    BSV_SRC = FIFE_SUBMOD / "Code/src_Fife/S3_RR_S6_WB.bsv"
    BACKUP  = FIFE_SUBMOD / "Code/src_Fife/S3_RR_S6_WB.bsv.post_fwd_bak"

    # Extract pre-forwarding BSV from git
    log(f"Extracting S3_RR_S6_WB.bsv from git commit {PRE_FWD_COMMIT}...")
    rc, out = run(
        f"git show {PRE_FWD_COMMIT}:Code/src_Fife/S3_RR_S6_WB.bsv",
        cwd=FIFE_SUBMOD
    )
    if rc != 0:
        err(f"git show failed: {out[-500:]}")
        return False

    pre_fwd_bsv = out

    # Backup current BSV
    shutil.copy(BSV_SRC, BACKUP)
    log("Backed up current S3_RR_S6_WB.bsv")

    # Write pre-forwarding version
    BSV_SRC.write_text(pre_fwd_bsv)
    log("Wrote pre-forwarding S3_RR_S6_WB.bsv")

    # Compile with BSC
    log("Compiling with BSC (this takes 3-5 minutes)...")
    fife_build = FIFE_SUBMOD / "Code/Build/Fife"
    bsc_path = ":".join([
        str(FIFE_SUBMOD / "Code/src_Top"),
        str(FIFE_SUBMOD / "Code/src_Fife"),
        str(FIFE_SUBMOD / "Code/src_Common"),
        str(FIFE_SUBMOD / "Code/vendor/bsc-contrib_Misc"),
        str(FIFE_SUBMOD / "Code/vendor/RVFI_DII_Types"),
        "+",
        str(MELODICA_SRC),
        str(MELODICA_SRC / "common"),
        str(MELODICA_SRC / "Fused_Op"),
        str(MELODICA_SRC / "lib"),
        str(MELODICA_SRC / "FtoP"),
        str(MELODICA_SRC / "QtoP"),
        str(MELODICA_SRC / "PtoF"),
        str(MELODICA_SRC / "PtoQ"),
        str(MELODICA_SRC / "Adder"),
        str(MELODICA_SRC / "Multiplier"),
        str(MELODICA_SRC / "Divider"),
    ])

    bsc_cmd = (
        f"{BSC_BIN} -u -elab -verilog "
        f"-bdir {fife_build}/build_v "
        f"-info-dir {fife_build}/build_v "
        f"-vdir {PRE_FWD_DIR} "
        f"-D RV32 -D STANDALONE "
        f"-keep-fires -aggressive-conditions -no-warn-action-shadowing "
        f"-opt-undetermined-vals -unspecified-to X "
        f"-p {bsc_path} "
        f"{FIFE_SUBMOD}/Code/src_Fife/S3_RR_S6_WB.bsv"
    )

    rc, out = run(bsc_cmd, cwd=fife_build, timeout=600)
    (SCRIPT_DIR / "results" / "bsc_pre_fwd_compile.log").write_text(out)

    # Restore
    shutil.copy(BACKUP, BSV_SRC)
    BACKUP.unlink()
    log("Restored post-forwarding S3_RR_S6_WB.bsv")

    if target.exists():
        ok(f"Pre-forwarding mkRR_WB.v generated: {target}")
        return True
    else:
        warn(f"BSC didn't produce mkRR_WB.v at {target}")
        warn("Trying full top-level compilation...")

        # Restore pre-fwd BSV for full compile
        BSV_SRC.write_text(pre_fwd_bsv)
        shutil.copy(BSV_SRC, BACKUP)

        bsc_cmd_full = bsc_cmd.replace(
            "S3_RR_S6_WB.bsv",
            f"{FIFE_SUBMOD}/Code/src_Top/Top.bsv"
        )
        rc, out = run(bsc_cmd_full, cwd=fife_build, timeout=900)
        (SCRIPT_DIR / "results" / "bsc_pre_fwd_full_compile.log").write_text(out)

        shutil.copy(BACKUP, BSV_SRC)
        BACKUP.unlink()

        if target.exists():
            ok(f"Pre-forwarding mkRR_WB.v generated via full compile: {target}")
            return True
        else:
            err(f"Failed to generate pre-forwarding mkRR_WB.v")
            err(f"Check: {SCRIPT_DIR}/results/bsc_pre_fwd_full_compile.log")
            return False


def build_yosys_script(variant, blif_path):
    """Build a Yosys script string for the given variant."""
    files = list(variant["verilog_files"])

    # Substitute pre-forwarding mkRR_WB.v if needed
    if "rr_wb_override" in variant:
        override = variant["rr_wb_override"]
        files = [f for f in files if f.name != "mkRR_WB.v"]
        files.append(override)

    read_lines = "\n".join(f"read_verilog {f}" for f in files)
    top = variant["top"]

    return textwrap.dedent(f"""
        {read_lines}
        hierarchy -check -top {top}
        synth -top {top} -flatten
        write_blif {blif_path}
        stat
    """).strip()


def run_abc_timing(blif_path, log_path):
    """
    Run yosys-abc on the BLIF file to get critical path timing.
    Returns (delay_ns, logic_levels, cell_count) or (None, None, None) on failure.
    """
    GENLIB_STR = str(GENLIB)
    abc_cmd = (
        f"yosys-abc -c "
        f"\"read_blif {blif_path}; "
        f"read_library {GENLIB_STR}; "
        f"strash; map; print_stats\""
    )
    try:
        rc, out = run(abc_cmd, timeout=600)
    except subprocess.TimeoutExpired:
        return None, None, None, "ABC timeout after 600s"

    log_path.write_text(out)

    # Parse: "netlist : i/o = .../... lat = 0 nd = N edge = M area = A delay = X.XX lev = L"
    m = re.search(r"delay\s*=\s*([\d.]+)\s+lev\s*=\s*(\d+)", out)
    if m:
        delay_ns = float(m.group(1))
        levels   = int(m.group(2))
        # Parse cell count (nd = N)
        cm = re.search(r"nd\s*=\s*(\d+)", out)
        cells = int(cm.group(1)) if cm else None
        return delay_ns, levels, cells, None
    else:
        err_m = re.search(r"(ERROR|error|failed|Failed).*", out)
        err_msg = err_m.group(0) if err_m else "Unknown ABC error"
        return None, None, None, err_msg


def analyze_variant(variant):
    """Run the full analysis pipeline for one design variant."""
    vid  = variant["id"]
    name = variant["name"]
    top  = variant["top"]
    blif_path = BLIF_DIR / variant["blif"]
    log_path  = RESULTS_DIR / variant["log"]
    yosys_log = RESULTS_DIR / f"{variant['blif'].replace('.blif', '_yosys.log')}"

    print(f"\n{'─'*70}")
    log(f"Variant {vid}: {name}")
    log(f"  Top module: {top}")
    print(f"{'─'*70}")

    # Check for pre-forwarding override
    if "rr_wb_override" in variant:
        override = variant["rr_wb_override"]
        if not override.exists():
            warn(f"  Pre-forwarding mkRR_WB.v not found at {override}")
            warn(f"  Skipping variant {vid}")
            return {"id": vid, "name": name, "error": f"Pre-forwarding mkRR_WB.v missing: {override}"}

    # Step 1: Yosys synthesis + BLIF export
    log(f"  Step 1: Yosys synthesis → {blif_path.name}")
    yosys_script = build_yosys_script(variant, blif_path)
    script_file = BLIF_DIR / f"{variant['blif'].replace('.blif', '.ys')}"
    script_file.write_text(yosys_script)

    try:
        rc, out = run(f"yosys {script_file}", timeout=1200)
    except subprocess.TimeoutExpired:
        err("  Yosys synthesis timed out after 20 minutes")
        return {"id": vid, "name": name, "error": "Yosys timeout"}

    yosys_log.write_text(out)

    # Extract cell count from Yosys stat
    yosys_cells = None
    cm = re.search(r"Number of cells:\s+(\d+)", out)
    if cm:
        yosys_cells = int(cm.group(1))

    if not blif_path.exists():
        err(f"  Yosys did not produce {blif_path}")
        last = out[-1000:]
        err(f"  Last output:\n{last}")
        return {"id": vid, "name": name, "error": f"Yosys failed: {last[-200:]}"}

    ok(f"  Yosys done — {blif_path.stat().st_size/1024:.0f} KB BLIF, {yosys_cells or '?'} cells (pre-mapping)")

    # Step 2: ABC technology mapping + timing
    log(f"  Step 2: ABC technology mapping → timing report")
    try:
        delay_ns, levels, abc_cells, abc_err = run_abc_timing(blif_path, log_path)
    except Exception as e:
        return {"id": vid, "name": name, "error": str(e)}

    if delay_ns is None:
        err(f"  ABC failed: {abc_err}")
        return {"id": vid, "name": name, "error": abc_err}

    max_mhz = round(1000.0 / delay_ns, 1) if delay_ns > 0 else None
    ok(f"  Critical path: {delay_ns:.3f} ns  |  Max freq: {max_mhz} MHz  |  Logic levels: {levels}")

    return {
        "id": vid,
        "name": name,
        "desc": variant["desc"],
        "top": top,
        "delay_ns": delay_ns,
        "max_mhz": max_mhz,
        "logic_levels": levels,
        "cells_pre_map": yosys_cells,
        "cells_mapped": abc_cells,
        "blif": str(blif_path),
        "log": str(log_path),
        "error": None,
    }


def write_markdown_summary(results):
    """Write the final markdown comparison report."""
    with open(SUMMARY_MD, "w") as f:
        f.write("# Critical Path Analysis — Actual Timing Results\n\n")
        f.write("> **Tool:** Yosys 0.33 + yosys-abc  \n")
        f.write("> **Library:** `generic45nm.genlib` — 45nm standard cell library  \n")
        f.write("> **Method:** RTL Verilog → `synth -flatten` + `write_blif` → `yosys-abc strash+map` → `print_stats`  \n\n")
        f.write("> **Unlike `ltp`** which counts gate hops across flip-flop boundaries through Bluespec\n")
        f.write("> scheduling wires, this approach performs true technology mapping and reports\n")
        f.write("> the actual worst-case combinatorial delay (ns) from FF output to FF input.\n\n")
        f.write("---\n\n")

        f.write("## Results Summary\n\n")
        f.write("| # | Design Variant | Critical Path (ns) | Max Freq (MHz) | Logic Levels | Cells (mapped) |\n")
        f.write("|---|---|---|---|---|---|\n")
        for r in results:
            if r.get("error"):
                f.write(f"| **{r['id']}** | {r['name']} | ❌ Error | — | — | — |\n")
            else:
                f.write(
                    f"| **{r['id']}** | {r['name']} "
                    f"| **{r['delay_ns']:.3f} ns** "
                    f"| {r['max_mhz']} MHz "
                    f"| {r['logic_levels']} "
                    f"| {r.get('cells_mapped', '?'):,} |\n"
                )

        f.write("\n---\n\n")
        f.write("## Per-Variant Details\n\n")
        for r in results:
            f.write(f"### Variant {r['id']}: {r['name']}\n\n")
            if r.get("error"):
                f.write(f"❌ **Error:** `{r['error']}`\n\n")
                continue
            f.write(f"**Description:** {r.get('desc', '')}  \n")
            f.write(f"**Top module:** `{r['top']}`  \n")
            f.write(f"**Critical path delay:** `{r['delay_ns']:.3f} ns`  \n")
            f.write(f"**Maximum clock frequency:** `{r['max_mhz']} MHz`  \n")
            f.write(f"**Logic levels (post-mapping):** `{r['logic_levels']}`  \n")
            f.write(f"**Cells pre-mapping:** `{r.get('cells_pre_map', 'N/A')}`  \n")
            f.write(f"**Cells mapped:** `{r.get('cells_mapped', 'N/A')}`  \n")
            f.write(f"**Log:** [`{Path(r['log']).name}`]({Path(r['log']).name})  \n\n")

        f.write("---\n\n")
        f.write("## Library Cell Delays (generic45nm.genlib)\n\n")
        f.write("| Cell | Delay (rise) | Delay (fall) |\n")
        f.write("|------|-------------|-------------|\n")
        delays = [
            ("$\\_NOT\\_",    "0.009 ns", "0.009 ns"),
            ("$\\_AND\\_",    "0.018 ns", "0.016 ns"),
            ("$\\_OR\\_",     "0.019 ns", "0.017 ns"),
            ("$\\_XOR\\_",    "0.028 ns", "0.028 ns"),
            ("$\\_NAND\\_",   "0.014 ns", "0.017 ns"),
            ("$\\_NOR\\_",    "0.017 ns", "0.014 ns"),
            ("$\\_MUX\\_",    "0.028 ns", "0.028 ns"),
            ("$\\_ANDNOT\\_", "0.018 ns", "0.016 ns"),
        ]
        for cell, rise, fall in delays:
            f.write(f"| `{cell}` | {rise} | {fall} |\n")

    ok(f"Summary written to {SUMMARY_MD}")


def print_summary_table(results):
    """Print a formatted comparison table to stdout."""
    print(f"\n{'='*80}")
    print(f"  CRITICAL PATH ANALYSIS — RESULTS SUMMARY")
    print(f"{'='*80}")
    header = f"{'#':<3} {'Variant':<40} {'Delay (ns)':>11} {'Max MHz':>9} {'Levels':>8}"
    print(header)
    print("-" * 74)
    for r in results:
        if r.get("error"):
            row = f"{r['id']:<3} {r['name']:<40} {'ERROR':>11} {'—':>9} {'—':>8}"
        else:
            row = (
                f"{r['id']:<3} {r['name']:<40} "
                f"{r['delay_ns']:>10.3f} "
                f"{r['max_mhz']:>9.1f} "
                f"{r['logic_levels']:>8}"
            )
        print(row)
    print("=" * 74)


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
def main():
    section("Critical Path Analysis — Yosys + yosys-abc + generic45nm.genlib")

    # Setup directories
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    BLIF_DIR.mkdir(parents=True, exist_ok=True)

    # Check prerequisites
    if not check_prereqs():
        sys.exit(1)

    # Generate pre-forwarding mkRR_WB.v
    pre_fwd_ok = generate_pre_forwarding_mkrr_wb()
    if not pre_fwd_ok:
        warn("Pre-forwarding variants (2 & 4) will be skipped")

    # Run all variants
    results = []
    for variant in VARIANTS:
        result = analyze_variant(variant)
        results.append(result)

    # Print summary
    print_summary_table(results)

    # Write markdown
    write_markdown_summary(results)

    ok(f"\nAll analyses complete!")
    ok(f"Summary:     {SUMMARY_MD}")
    ok(f"Result logs: {RESULTS_DIR}/")
    ok(f"BLIF files:  {BLIF_DIR}/")


if __name__ == "__main__":
    main()
