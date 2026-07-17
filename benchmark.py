import os
import subprocess
import sys

def run_test(test_name, hex_path):
    print(f"Running test: {test_name} ...")
    build_dir = "/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/Build/Fife"
    
    # Symlink the hex file
    cmd = f"MEMHEX32={hex_path} ./exe_Fife_RV32_verilator +tohost"
    
    result = subprocess.run(cmd, shell=True, cwd=build_dir, capture_output=True, text=True)
    
    cycle = 0
    inst = 0
    stalls = 0
    flushes = 0
    
    for line in result.stdout.splitlines():
        if line.startswith("BENCHMARK_CYCLES:"):
            cycle = int(line.split(":")[1].strip())
        elif line.startswith("BENCHMARK_INSTRET:"):
            inst = int(line.split(":")[1].strip())
        elif line.startswith("BENCHMARK_STALL:"):
            stalls = int(line.split(":")[1].strip())
        elif line.startswith("BENCHMARK_FLUSH:"):
            flushes = int(line.split(":")[1].strip())

    ipc = inst / cycle if cycle > 0 else 0
    print(f"  Cycles: {cycle}")
    print(f"  Instructions Retired: {inst}")
    print(f"  IPC: {ipc:.4f}")
    print(f"  Pipeline Stalls (Data Hazards): {stalls}")
    print(f"  Control Flushes (Mispredicts): {flushes}")
    
    return cycle, inst, ipc, stalls, flushes

if __name__ == "__main__":
    print("Running tests without recompiling...")
    build_dir = "/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/Build/Fife"
    # subprocess.run("make full_clean", shell=True, cwd=build_dir, stdout=subprocess.DEVNULL)
    # subprocess.run("make v_compile v_link", shell=True, cwd=build_dir, check=True, stdout=subprocess.DEVNULL)

    tests = [
        ("posit_basic", "/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs/posit_basic.memhex32"),
        ("posit_convert", "/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs/posit_convert.memhex32"),
        ("posit_dot_product", "/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs/posit_dot_product.memhex32"),
        ("posit_mac_loop", "/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs/posit_mac_loop.memhex32"),
        ("posit_matmul", "/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs/posit_matmul.memhex32"),
        ("posit_poly_eval", "/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs/posit_poly_eval.memhex32"),
        ("posit_conv1d", "/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs/posit_conv1d.memhex32"),
        ("posit_iir_filter", "/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs/posit_iir_filter.memhex32")
    ]
    
    results = {}
    for name, path in tests:
        results[name] = run_test(name, path)
    
    summary = "\n=== Benchmark Summary ===\n"
    for name in results:
        cycle, inst, ipc, stalls, flushes = results[name]
        summary += f"{name:10} | Cycles: {cycle:<8} | IPC: {ipc:.4f} | Stalls: {stalls:<6} | Flushes: {flushes:<6}\n"
    
    print(summary)
    
    # Write to a markdown artifact
    with open("benchmark_results.md", "w") as f:
        f.write("# Benchmark Results (Pre-Implementation)\n```\n")
        f.write(summary)
        f.write("```\n")
