#!/usr/bin/env bash
# run_benchmarks.sh
# Run all benchmarks and collect performance metrics.
# Usage:  ./run_benchmarks.sh [baseline|forwarding] [simulator_path]
#
# Metrics extracted from simulation log:
#   - Total cycles (from +tohost output: "GPIO tohost" line)
#   - Instructions retired (count of ftrace RET lines)
#   - Stall cycles (count of ftrace RR.S lines)
#   - PASS/FAIL status

set -euo pipefail

VARIANT="${1:-baseline}"
SIM="${2:-/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/Build/Fife/exe_Fife_RV32_verilator}"
TESTDIR="/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs"
BUILDDIR="/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/Build/Fife"
OUTDIR="/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/progress"

CSV="${OUTDIR}/benchmark_results_${VARIANT}.csv"

echo "variant,test,status,cycles,instrs_retired,stall_cycles,ipc,stall_rate" > "$CSV"

TESTS=(
    "posit_basic"
    "posit_convert"
    "posit_dot_product"
    "raw_int_single"
    "raw_int_chain"
    "raw_int_backtoback"
    "raw_int_loop"
    "raw_worst_case"
    "raw_posit_chain"
    "raw_mixed"
)

for test in "${TESTS[@]}"; do
    MHX="${TESTDIR}/${test}.memhex32"
    if [ ! -f "$MHX" ]; then
        echo "SKIP: $test (no .memhex32 found)"
        continue
    fi

    echo -n "Running $test ... "

    # Symlink test file
    ln -s -f "$MHX" "${BUILDDIR}/test.memhex32"

    # Run simulation with logging, 30s timeout
    LOG="${OUTDIR}/logs/${VARIANT}_${test}.log"
    mkdir -p "${OUTDIR}/logs"

    set +e
    timeout 60 "$SIM" +v2 +tohost +log > "${LOG}.sim" 2>&1
    SIMRET=$?
    set -e

    # Copy log file
    if [ -f "${BUILDDIR}/log.txt" ]; then
        cp "${BUILDDIR}/log.txt" "$LOG"
    else
        touch "$LOG"
    fi

    # Parse simulation stdout for PASS/FAIL and cycles
    STATUS="UNKNOWN"
    CYCLES=0
    if grep -q "GPIO tohost PASS" "${LOG}.sim" 2>/dev/null; then
        STATUS="PASS"
    elif grep -q "GPIO tohost FAIL" "${LOG}.sim" 2>/dev/null; then
        STATUS="FAIL"
    elif [ $SIMRET -eq 124 ]; then
        STATUS="TIMEOUT"
    fi

    # Extract cycle count from sim stdout (look for "cur_cycle" or count lines)
    # The simulator prints cycle on the tohost line: "Cycle: NNN  GPIO tohost ..."
    CYCLE_LINE=$(grep "cur_cycle\|Cycle\|cycle" "${LOG}.sim" 2>/dev/null | grep -i "tohost\|PASS\|FAIL" | head -1 || true)
    if [ -n "$CYCLE_LINE" ]; then
        CYCLES=$(echo "$CYCLE_LINE" | grep -oP '\d+' | head -1)
    fi

    # Parse log.txt for metrics
    INSTRS_RETIRED=0
    STALL_CYCLES=0
    if [ -s "$LOG" ]; then
        INSTRS_RETIRED=$(grep -c "RET\." "$LOG" 2>/dev/null || echo 0)
        STALL_CYCLES=$(grep -c "RR\.S" "$LOG" 2>/dev/null || echo 0)
    fi

    # Compute IPC and stall rate
    IPC="N/A"
    STALL_RATE="N/A"
    if [ "$INSTRS_RETIRED" -gt 0 ] && [ "$STALL_CYCLES" -ge 0 ]; then
        TOTAL_ACTIVE=$((INSTRS_RETIRED + STALL_CYCLES))
        IPC=$(python3 -c "print(f'{$INSTRS_RETIRED / max(1,$TOTAL_ACTIVE):.3f}')" 2>/dev/null || echo "N/A")
        STALL_RATE=$(python3 -c "print(f'{$STALL_CYCLES / max(1,$TOTAL_ACTIVE):.3f}')" 2>/dev/null || echo "N/A")
    fi

    echo "$STATUS (retired=$INSTRS_RETIRED stalls=$STALL_CYCLES)"
    echo "${VARIANT},${test},${STATUS},${CYCLES},${INSTRS_RETIRED},${STALL_CYCLES},${IPC},${STALL_RATE}" >> "$CSV"
done

echo ""
echo "Results written to: $CSV"
echo ""
cat "$CSV"
