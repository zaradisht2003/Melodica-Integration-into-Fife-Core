#!/bin/bash
# =============================================================================
# run_all_sta.sh — Master script for all 5 critical path analyses
#
# This script:
#   1. Verifies prerequisites (yosys, bsc)
#   2. Extracts pre-forwarding S3_RR_S6_WB.bsv from git and recompiles it
#      to get the pre-forwarding mkRR_WB.v (needed for variants 2 & 4)
#   3. Runs Yosys STA for all 5 design variants
#   4. Parses results and generates the summary report
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VERILOG_DIR="$REPO_ROOT/Learn_Bluespec_and_RISCV_Design/Code/Build/Fife/verilog"
FIFE_BUILD_DIR="$REPO_ROOT/Learn_Bluespec_and_RISCV_Design/Code/Build/Fife"
FIFE_SRC_DIR="$REPO_ROOT/Learn_Bluespec_and_RISCV_Design/Code/src_Fife"
BSC_BIN="$REPO_ROOT/bsc/bin/bsc"
BSC_LIB_VERILOG="$REPO_ROOT/bsc/lib/Verilog"
LIBERTY="$REPO_ROOT/generic45nm.lib"
PRE_FWD_VERILOG="$SCRIPT_DIR/pre_fwd_verilog"
RESULTS="$SCRIPT_DIR/results"
LOG_FILE="$SCRIPT_DIR/run_all_sta.log"

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*" | tee -a "$LOG_FILE"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[ERR]${NC} $*" | tee -a "$LOG_FILE"; }

echo "" | tee "$LOG_FILE"
log "====================================================================="
log "  Critical Path Analysis — Yosys STA + generic45nm.lib"
log "====================================================================="
echo "" | tee -a "$LOG_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 0: Prerequisites check
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 0: Checking prerequisites..."

if ! command -v yosys &>/dev/null; then
    err "yosys not found in PATH. Install with: apt install yosys"
    exit 1
fi
YOSYS_VER=$(yosys --version 2>&1 | head -1)
ok "Yosys: $YOSYS_VER"

if [ ! -f "$BSC_BIN" ]; then
    err "bsc not found at $BSC_BIN"
    exit 1
fi
ok "BSC compiler: $BSC_BIN"

if [ ! -f "$LIBERTY" ]; then
    err "Liberty file not found: $LIBERTY"
    exit 1
fi
ok "Liberty: $LIBERTY"

mkdir -p "$PRE_FWD_VERILOG" "$RESULTS"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: Extract and recompile pre-forwarding mkRR_WB.v
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "STEP 1: Generating pre-forwarding mkRR_WB.v..."
log "  Source: git commit 2aa5711 of Learn_Bluespec_and_RISCV_Design"

FIFE_SUBMODULE="$REPO_ROOT/Learn_Bluespec_and_RISCV_Design"
PRE_FWD_COMMIT="2aa5711"  # "Integrate posit arithmetic from Melodica" — no forwarding

# Save the current S3_RR_S6_WB.bsv (post-forwarding)
CURRENT_BSV="$FIFE_SRC_DIR/S3_RR_S6_WB.bsv"
BACKUP_BSV="$FIFE_SRC_DIR/S3_RR_S6_WB.bsv.post_fwd_backup"

if [ ! -f "$PRE_FWD_VERILOG/mkRR_WB.v" ]; then
    log "  Backing up current S3_RR_S6_WB.bsv..."
    cp "$CURRENT_BSV" "$BACKUP_BSV"

    log "  Extracting pre-forwarding BSV from git ($PRE_FWD_COMMIT)..."
    cd "$FIFE_SUBMODULE"
    git show "${PRE_FWD_COMMIT}:Code/src_Fife/S3_RR_S6_WB.bsv" > "$CURRENT_BSV"
    ok "  Extracted pre-forwarding S3_RR_S6_WB.bsv"

    log "  Recompiling S3_RR_S6_WB.bsv with BSC to generate mkRR_WB.v..."
    cd "$FIFE_BUILD_DIR"

    # Source paths needed for BSC compilation (from Include.mk)
    MELODICA_SRC="$REPO_ROOT/Melodica/src_bsv"
    SRC_CPU="$FIFE_SUBMODULE/Code/src_Fife"
    SRC_TOP="$FIFE_SUBMODULE/Code/src_Top"
    SRC_COMMON="$FIFE_SUBMODULE/Code/src_Common"
    MISC_LIBS="$FIFE_SUBMODULE/Code/vendor/bsc-contrib_Misc"
    RVFI_DII="$FIFE_SUBMODULE/Code/vendor/RVFI_DII_Types"

    BSCPATH="${SRC_TOP}:${SRC_CPU}:${SRC_COMMON}:${MISC_LIBS}:${RVFI_DII}:+:${MELODICA_SRC}:${MELODICA_SRC}/common:${MELODICA_SRC}/Fused_Op:${MELODICA_SRC}/lib:${MELODICA_SRC}/FtoP:${MELODICA_SRC}/QtoP:${MELODICA_SRC}/PtoF:${MELODICA_SRC}/PtoQ:${MELODICA_SRC}/Adder:${MELODICA_SRC}/Multiplier:${MELODICA_SRC}/Divider"

    mkdir -p build_v verilog

    # Compile only the modified file (incremental)
    "$BSC_BIN" -u -elab -verilog \
        -bdir build_v -info-dir build_v -vdir "$PRE_FWD_VERILOG" \
        -D RV32 -D STANDALONE \
        -keep-fires -aggressive-conditions -no-warn-action-shadowing \
        -opt-undetermined-vals -unspecified-to X \
        -p "$BSCPATH" \
        "$SRC_CPU/S3_RR_S6_WB.bsv" 2>&1 | tee -a "$LOG_FILE" || {
            warn "BSC compilation had warnings/errors above — checking if mkRR_WB.v was produced..."
        }

    if [ -f "$PRE_FWD_VERILOG/mkRR_WB.v" ]; then
        ok "  Pre-forwarding mkRR_WB.v generated: $PRE_FWD_VERILOG/mkRR_WB.v"
    else
        # Try compiling from top-level to get mkRR_WB.v as a side effect
        warn "  Direct compile didn't produce mkRR_WB.v, trying full compilation..."
        "$BSC_BIN" -u -elab -verilog \
            -bdir build_v -info-dir build_v -vdir "$PRE_FWD_VERILOG" \
            -D RV32 -D STANDALONE \
            -keep-fires -aggressive-conditions -no-warn-action-shadowing \
            -opt-undetermined-vals -unspecified-to X \
            -p "$BSCPATH" \
            "$SRC_TOP/Top.bsv" 2>&1 | tee -a "$LOG_FILE"

        if [ -f "$PRE_FWD_VERILOG/mkRR_WB.v" ]; then
            ok "  Pre-forwarding mkRR_WB.v generated via full compile"
        else
            err "  Failed to generate pre-forwarding mkRR_WB.v"
            # Restore original and exit
            cp "$BACKUP_BSV" "$CURRENT_BSV"
            exit 1
        fi
    fi

    log "  Restoring post-forwarding S3_RR_S6_WB.bsv..."
    cp "$BACKUP_BSV" "$CURRENT_BSV"
    rm "$BACKUP_BSV"
    ok "  Post-forwarding BSV restored"
else
    ok "  Pre-forwarding mkRR_WB.v already exists — skipping recompile"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Helper function: run a Yosys STA script and save the log
# ─────────────────────────────────────────────────────────────────────────────
run_sta() {
    local variant_id="$1"
    local variant_name="$2"
    local script="$3"
    local log_out="$4"

    log ""
    log "─────────────────────────────────────────────────────────────────"
    log "VARIANT $variant_id: $variant_name"
    log "  Script: $script"
    log "  Output: $log_out"
    log "─────────────────────────────────────────────────────────────────"

    if yosys "$script" > "$log_out" 2>&1; then
        # Extract key timing line from the log (ABC print_stats -t output)
        TIMING=$(grep -E "ABC:.*netlist.*delay|Longest topological path|ltp_length" "$log_out" | tail -5)
        ok "  Completed. Key timing output:"
        echo "$TIMING" | while IFS= read -r line; do
            echo "    $line" | tee -a "$LOG_FILE"
        done
    else
        YOSYS_ERR=$(tail -10 "$log_out")
        warn "  Yosys returned non-zero exit. Last lines:"
        echo "$YOSYS_ERR" | while IFS= read -r line; do
            echo "    $line" | tee -a "$LOG_FILE"
        done
        warn "  Check $log_out for full details"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: Run all 5 STA analyses
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "STEP 2: Running Yosys STA for all 5 design variants..."
log "  (This may take 5–30 minutes per variant for large designs)"
log ""

run_sta 1 "Melodica Standalone" \
    "$SCRIPT_DIR/sta_melodica.ys" \
    "$RESULTS/melodica_sta.log"

run_sta 2 "Fife Core — Pre-Forwarding" \
    "$SCRIPT_DIR/sta_fife_pre_fwd.ys" \
    "$RESULTS/fife_pre_fwd_sta.log"

run_sta 3 "Fife Core — Post-Forwarding" \
    "$SCRIPT_DIR/sta_fife_post_fwd.ys" \
    "$RESULTS/fife_post_fwd_sta.log"

run_sta 4 "Integrated System — Pre-Forwarding" \
    "$SCRIPT_DIR/sta_integrated_pre_fwd.ys" \
    "$RESULTS/integrated_pre_fwd_sta.log"

run_sta 5 "Integrated System — Post-Forwarding" \
    "$SCRIPT_DIR/sta_integrated_post_fwd.ys" \
    "$RESULTS/integrated_post_fwd_sta.log"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3: Parse results and generate summary
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "STEP 3: Parsing results and generating summary..."

cd "$SCRIPT_DIR"
python3 parse_sta_results.py 2>&1 | tee -a "$LOG_FILE"

log ""
log "====================================================================="
log "  All analyses complete!"
log "  Summary:   $SCRIPT_DIR/critical_path_summary.md"
log "  Full logs: $RESULTS/"
log "  Run log:   $LOG_FILE"
log "====================================================================="
