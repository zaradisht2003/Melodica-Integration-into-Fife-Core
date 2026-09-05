import os
import subprocess

REPO_ROOT = "/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core"
BUILD_DIR = os.path.join(REPO_ROOT, "Learn_Bluespec_and_RISCV_Design/Code/Build/Fife")
TEST_DIR = os.path.join(REPO_ROOT, "Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs")

tests = [
    ("posit_basic", os.path.join(TEST_DIR, "posit_basic.memhex32")),
    ("posit_convert", os.path.join(TEST_DIR, "posit_convert.memhex32")),
    ("posit_dot_product", os.path.join(TEST_DIR, "posit_dot_product.memhex32")),
    ("posit_mac_loop", os.path.join(TEST_DIR, "posit_mac_loop.memhex32")),
    ("posit_matmul", os.path.join(TEST_DIR, "posit_matmul.memhex32")),
    ("posit_poly_eval", os.path.join(TEST_DIR, "posit_poly_eval.memhex32")),
    ("posit_conv1d", os.path.join(TEST_DIR, "posit_conv1d.memhex32")),
    ("posit_iir_filter", os.path.join(TEST_DIR, "posit_iir_filter.memhex32")),
]

def run_all_tests():
    results = []
    print(f"{'Test Program':<20} | {'Status':<8} | {'Cycles':<10} | {'Insts':<10} | {'IPC':<8}")
    print("-" * 65)
    for name, hex_path in tests:
        cmd = f"MEMHEX32={hex_path} timeout 30 ./exe_Fife_RV32_verilator +tohost"
        proc = subprocess.Popen(cmd, shell=True, cwd=BUILD_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout, stderr = proc.communicate()
        
        cycle = 0
        inst = 0
        passed = False
        
        for line in stdout.splitlines():
            if line.startswith("BENCHMARK_CYCLES:"):
                cycle = int(line.split(":")[1].strip())
            elif line.startswith("BENCHMARK_INSTRET:"):
                inst = int(line.split(":")[1].strip())
                passed = True
                
        status = "PASS" if passed or proc.returncode == 0 else "FAIL"
        ipc = (inst / cycle) if cycle > 0 else 0.0
        print(f"{name:<20} | {status:<8} | {cycle:<10} | {inst:<10} | {ipc:<8.4f}")
        results.append({
            "name": name,
            "status": status,
            "cycles": cycle,
            "insts": inst,
            "ipc": ipc
        })
    return results

if __name__ == "__main__":
    run_all_tests()
