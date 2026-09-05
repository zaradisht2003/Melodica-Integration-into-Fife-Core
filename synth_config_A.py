import os
import subprocess
import re

REPO_ROOT = "/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core"
BUILD_DIR = os.path.join(REPO_ROOT, "Learn_Bluespec_and_RISCV_Design/Code/Build/Fife")
BSC_PRIM_DIR = os.path.join(REPO_ROOT, "bsc/lib/Verilog")
VERILOG_DIR = os.path.join(BUILD_DIR, "verilog")
LIB_FILE = os.path.join(REPO_ROOT, "generic45nm_fixed.lib")
GENLIB_FILE = os.path.join(REPO_ROOT, "generic45nm.genlib")

v_files_melodica = [
    os.path.join(BSC_PRIM_DIR, "FIFO1.v"),
    os.path.join(BSC_PRIM_DIR, "FIFO2.v"),
    os.path.join(BSC_PRIM_DIR, "SizedFIFO.v"),
    os.path.join(BSC_PRIM_DIR, "RegFile.v"),
    os.path.join(VERILOG_DIR, "module_fn_twosC_quire.v"),
    os.path.join(VERILOG_DIR, "mkQuire.v"),
    os.path.join(VERILOG_DIR, "mkMultiplier.v"),
    os.path.join(VERILOG_DIR, "mkNormalizer.v"),
    os.path.join(VERILOG_DIR, "mkExtracter.v"),
    os.path.join(VERILOG_DIR, "mkFtoP_PNE.v"),
    os.path.join(VERILOG_DIR, "mkPtoF_PNE.v"),
    os.path.join(VERILOG_DIR, "mkPositCore.v"),
]

v_files_mktop = v_files_melodica + [
    os.path.join(VERILOG_DIR, "mkGPRs_synth.v"),
    os.path.join(VERILOG_DIR, "mkGPR_Logging_synth.v"),
    os.path.join(VERILOG_DIR, "mkDecode.v"),
    os.path.join(VERILOG_DIR, "mkFetch.v"),
    os.path.join(VERILOG_DIR, "mkCSRs.v"),
    os.path.join(VERILOG_DIR, "mkRetire.v"),
    os.path.join(VERILOG_DIR, "mkEX_Control.v"),
    os.path.join(VERILOG_DIR, "mkEX_Int.v"),
    os.path.join(VERILOG_DIR, "mkEX_Posit.v"),
    os.path.join(VERILOG_DIR, "mkRVFI_Report.v"),
    os.path.join(VERILOG_DIR, "mkCPU.v"),
    os.path.join(VERILOG_DIR, "mkRR_WB.v"),
    os.path.join(VERILOG_DIR, "mkTop.v"),
]

def run_synthesis_blif(top, v_list, prefix="es6_rs3"):
    print(f"\n========================================\nSynthesizing {top} ({prefix})\n========================================")
    valid_files = [f for f in v_list if os.path.exists(f)]
    read_cmd = " ".join(valid_files)
    blif_file = os.path.join(REPO_ROOT, f"{top}_{prefix}.blif")
    yosys_log = os.path.join(REPO_ROOT, f"yosys_{top}_{prefix}.log")
    abc_log = os.path.join(REPO_ROOT, f"abc_{top}_{prefix}.log")
    
    # 1. Yosys pass to generate BLIF
    ys_script = f"read_verilog -I {BSC_PRIM_DIR} {read_cmd}; hierarchy -check -top {top}; synth -top {top} -flatten; write_blif {blif_file}"
    subprocess.run(f"yosys -p '{ys_script}' > {yosys_log} 2>&1", shell=True, cwd=REPO_ROOT)
    
    # Extract cell count from yosys log
    cells = "N/A"
    with open(yosys_log) as f:
        yosys_txt = f.read()
    m_cells = re.search(r"Number of cells:\s+(\d+)", yosys_txt)
    if m_cells:
        cells = int(m_cells.group(1))
        
    # 2. ABC pass on BLIF using liberty / genlib
    abc_cmd = f"yosys-abc -c 'read_blif {blif_file}; read_library {GENLIB_FILE}; strash; map; print_stats'"
    out = subprocess.run(abc_cmd, shell=True, capture_output=True, text=True, cwd=REPO_ROOT)
    with open(abc_log, "w") as f:
        f.write(out.stdout)
        f.write(out.stderr)
        
    area = "N/A"
    delay = "N/A"
    levels = "N/A"
    
    m_abc = re.search(r"area\s*=\s*([\d.]+)\s+delay\s*=\s*([\d.]+)\s+lev\s*=\s*(\d+)", out.stdout)
    if m_abc:
        area = float(m_abc.group(1))
        delay = float(m_abc.group(2))
        levels = int(m_abc.group(3))
        
    print(f"Top: {top:<12} | Cells: {cells:<8} | Area: {area:<12} | Delay: {delay:<8} ns | Levels: {levels}")
    return {"top": top, "cells": cells, "area": area, "delay": delay, "levels": levels}

if __name__ == "__main__":
    r1 = run_synthesis_blif("mkQuire", v_files_melodica, "es6_rs3")
    r2 = run_synthesis_blif("mkPositCore", v_files_melodica, "es6_rs3")
    r3 = run_synthesis_blif("mkTop", v_files_mktop, "es6_rs3")
