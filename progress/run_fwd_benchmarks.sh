#!/usr/bin/env bash
# run_fwd_benchmarks.sh
# Run all benchmarks against the CURRENT binary (forwarding build) and
# collect performance metrics from the simulation log.
# Usage:  ./run_fwd_benchmarks.sh [output_csv]
#
# Metrics extracted from simulation log (log.txt written by +log flag):
#   - Retired instructions: count of unique Trace lines with RET.* stage
#   - Stall cycles:         count of Trace lines with RR.S stage
#   - Active cycles:        last_ret_cycle - first_ret_cycle + 1
#   - IPC:                  retired / active_cycles
#   - Stall %:              100 * stalls / (stalls + retired)
#   - PASS/FAIL:            from sim stdout "GPIO tohost"

set -euo pipefail

SIM="/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/Build/Fife/exe_Fife_RV32_verilator"
TESTDIR="/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/src_Fife/test_programs"
BUILDDIR="/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Learn_Bluespec_and_RISCV_Design/Code/Build/Fife"
OUTDIR="/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/progress"
LOGDIR="${OUTDIR}/logs/forwarding"
CSV="${1:-${OUTDIR}/benchmark_results_forwarding.csv}"

mkdir -p "${LOGDIR}"

echo "test,status,retired,stalls,active_cycles,ipc,stall_rate_pct" > "${CSV}"

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
    if [ ! -f "${MHX}" ]; then
        echo "SKIP: ${test} (no .memhex32 found)"
        continue
    fi

    echo -n "Running ${test} ... "

    # Run simulation with logging enabled
    SIM_OUT="${LOGDIR}/${test}.sim_out"
    LOG="${LOGDIR}/${test}.log"

    (
        cd "${BUILDDIR}"
        # Symlink test file into build dir
        ln -sf "${MHX}" "test.memhex32"

        # Run simulation with logging enabled
        set +e
        timeout 120 ./exe_Fife_RV32_verilator +log > "${SIM_OUT}" 2>&1
        SIMRET=$?
        set -e

        # Copy the log.txt written by the simulator
        if [ -f "log.txt" ]; then
            cp "log.txt" "${LOG}"
        else
            touch "${LOG}"
        fi
        echo "$SIMRET" > simret.tmp
    )
    SIMRET=$(cat "${BUILDDIR}/simret.tmp")

    # Determine PASS/FAIL from sim stdout
    STATUS="UNKNOWN"
    if grep -q "GPIO tohost PASS" "${SIM_OUT}" 2>/dev/null; then
        STATUS="PASS"
    elif grep -q "GPIO tohost FAIL" "${SIM_OUT}" 2>/dev/null; then
        STATUS="FAIL"
    elif [ "${SIMRET}" -eq 124 ]; then
        STATUS="TIMEOUT"
    fi

    # Parse log.txt using collect_metrics.py
    METRICS=$(python3 "${OUTDIR}/collect_metrics.py" "${LOG}" 2>/dev/null || echo "0 0 0 0.0 0.0")
    RETIRED=$(echo "${METRICS}" | grep "Retired" | grep -oP '\d+' | head -1 || echo 0)
    STALLS=$(echo "${METRICS}"  | grep "Stall cycles" | grep -oP '\d+' | head -1 || echo 0)
    ACTIVE=$(echo "${METRICS}"  | grep "Active" | grep -oP '\d+' | head -1 || echo 0)
    IPC=$(echo "${METRICS}"     | grep "IPC" | grep -oP '[0-9.]+' | head -1 || echo 0)
    STALL_RATE=$(echo "${METRICS}" | grep "Stall rate" | grep -oP '[0-9.]+%' | head -1 || echo "0%")
    # Convert "X.X%" -> number
    STALL_PCT=$(echo "${STALL_RATE}" | tr -d '%')

    echo "${STATUS} (retired=${RETIRED} stalls=${STALLS} active=${ACTIVE} IPC=${IPC})"
    echo "${test},${STATUS},${RETIRED},${STALLS},${ACTIVE},${IPC},${STALL_PCT}" >> "${CSV}"
done

echo ""
echo "Results written to: ${CSV}"
echo ""
cat "${CSV}"
