import os
import subprocess
import re

REPO_ROOT = "/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core"
BUILD_DIR = os.path.join(REPO_ROOT, "Learn_Bluespec_and_RISCV_Design/Code/Build/Fife")
BSC_PRIM_DIR = os.path.join(REPO_ROOT, "bsc/lib/Verilog")
VERILOG_DIR = os.path.join(BUILD_DIR, "verilog")
LIB_FILE = os.path.join(REPO_ROOT, "generic45nm_fixed.lib")

# Ensure all top level verilog modules exist
print("Generating verilog for mktop/mkCPU if needed...")
bsc_path = ":".join([
    os.path.join(REPO_ROOT, "Learn_Bluespec_and_RISCV_Design/Code/src_Top"),
    os.path.join(REPO_ROOT, "Learn_Bluespec_and_RISCV_Design/Code/src_Fife"),
    os.path.join(REPO_ROOT, "Learn_Bluespec_and_RISCV_Design/Code/src_Common"),
    os.path.join(REPO_ROOT, "Learn_Bluespec_and_RISCV_Design/Code/vendor/bsc-contrib_Misc"),
    os.path.join(REPO_ROOT, "Learn_Bluespec_and_RISCV_Design/Code/vendor/RVFI_DII_Types"),
    "+",
    os.path.join(REPO_ROOT, "Melodica/src_bsv"),
    os.path.join(REPO_ROOT, "Melodica/src_bsv/common"),
    os.path.join(REPO_ROOT, "Melodica/src_bsv/Fused_Op"),
    os.path.join(REPO_ROOT, "Melodica/src_bsv/lib"),
    os.path.join(REPO_ROOT, "Melodica/src_bsv/FtoP"),
    os.path.join(REPO_ROOT, "Melodica/src_bsv/QtoP"),
    os.path.join(REPO_ROOT, "Melodica/src_bsv/PtoF"),
    os.path.join(REPO_ROOT, "Melodica/src_bsv/PtoQ"),
    os.path.join(REPO_ROOT, "Melodica/src_bsv/Adder"),
    os.path.join(REPO_ROOT, "Melodica/src_bsv/Multiplier"),
    os.path.join(REPO_ROOT, "Melodica/src_bsv/Divider"),
])

bsc_cmd = (
    f"{os.path.join(REPO_ROOT, 'bsc/bin/bsc')} -u -elab -verilog "
    f"-bdir {BUILD_DIR}/build_v "
    f"-info-dir {BUILD_DIR}/build_v "
    f"-vdir {VERILOG_DIR} "
    f"-D RV32 -D STANDALONE "
    f"-keep-fires -aggressive-conditions -no-warn-action-shadowing "
    f"-opt-undetermined-vals -unspecified-to X "
    f"-p {bsc_path} "
    f"{os.path.join(REPO_ROOT, 'Learn_Bluespec_and_RISCV_Design/Code/src_Top/Top.bsv')}"
)
subprocess.run(bsc_cmd, shell=True, cwd=BUILD_DIR, stdout=subprocess.DEVNULL)

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

v_files_mkcpu = v_files_melodica + [
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

def run_synth(top, v_list, prefix="es4_rs11"):
    print(f"\n========================================\nSynthesizing {top} ({prefix})\n========================================")
    read_cmd = " ".join(v_list)
    log_file = os.path.join(REPO_ROOT, f"synth_{top}_{prefix}.log")
    ys_path = os.path.join(REPO_ROOT, f"synth_script_{top}_{prefix}.ys")
    
    yosys_script = f"""
read_verilog -I {BSC_PRIM_DIR} {read_cmd}
hierarchy -check -top {top}
synth -top {top} -flatten
dfflibmap -liberty {LIB_FILE}
abc -liberty {LIB_FILE} -script "+read_lib,{LIB_FILE};strash;dch;map;topo;buffer;upsize;dnsize;stime -p;print_stats -t"
stat -liberty {LIB_FILE}
"""
    with open(ys_path, "w") as f:
        f.write(yosys_script)
        
    subprocess.run(f"yosys -s {ys_path} > {log_file} 2>&1", shell=True, cwd=REPO_ROOT)
    print(f"  Synthesis completed, log written to {log_file}")
    
    with open(log_file) as f:
        text = f.read()
        
    cells = "N/A"
    area = "N/A"
    delay = "N/A"
    levels = "N/A"
    
    m_cells = re.search(r"Number of cells:\s+(\d+)", text)
    if m_cells:
        cells = int(m_cells.group(1))
        
    m_abc = re.search(r"ABC:\s+netlist\s*:\s*i/o\s*=\s*[\d/]+\s+lat\s*=\s*\d+\s+nd\s*=\s*(\d+)\s+edge\s*=\s*\d+\s+area\s*=\s*([\d\.]+)\s+delay\s*=\s*([\d\.]+)\s+lev\s*=\s*(\d+)", text)
    if m_abc:
        area = float(m_abc.group(2))
        delay = float(m_abc.group(3)) / 1000.0 if float(m_abc.group(3)) > 10 else float(m_abc.group(3))
        levels = int(m_abc.group(4))
        
    print(f"  Result -> Top: {top:<12} | Cells: {cells:<8} | Area: {area:<12} | Delay: {delay:<8} ns | Levels: {levels}")
    return {"top": top, "cells": cells, "area": area, "delay": delay, "levels": levels}

if __name__ == "__main__":
    r_quire = run_synth("mkQuire", v_files_melodica, "es4_rs11")
    r_core  = run_synth("mkPositCore", v_files_melodica, "es4_rs11")
    r_cpu   = run_synth("mkCPU", v_files_mkcpu, "es4_rs11")
