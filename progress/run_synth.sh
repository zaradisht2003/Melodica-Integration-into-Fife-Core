#!/bin/bash

# Ensure we are in the progress directory
cd "$(dirname "$0")"

# Output file for synthesis results
OUT_FILE="synthesis_results.txt"
echo "Synthesis Results" > $OUT_FILE
echo "=================" >> $OUT_FILE

# Function to synthesize the current branch
run_synthesis() {
    local branch_name=$1
    echo "Synthesizing branch: $branch_name"
    echo "--------------------------------" >> $OUT_FILE
    echo "Branch: $branch_name" >> $OUT_FILE
    
    # Fix the Makefile space bug if present
    sed -i 's/BSCPATH += :$(MELODICA_SRC)/BSCPATH := $(BSCPATH):$(MELODICA_SRC)/g' ../Learn_Bluespec_and_RISCV_Design/Code/Build/Include.mk
    
    # Generate Verilog for the current branch
    (
      cd ../Learn_Bluespec_and_RISCV_Design/Code/Build/Fife
      PATH=/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/bsc/bin:$PATH make v_compile
    )
    
    # Run yosys and extract ltp output
    yosys -p "hierarchy -check -top mkCPU; synth -top mkCPU; ltp; stat" ../Learn_Bluespec_and_RISCV_Design/Code/Build/Fife/verilog/*.v > yosys_out.log 2>&1
    
    # Extract longest topological path
    LTP=$(grep -i "Longest topological path" yosys_out.log | tail -n 1)
    echo "  $LTP" >> $OUT_FILE
    
    # Extract cell count (approximate logic size)
    CELLS=$(grep -A 20 "Number of cells:" yosys_out.log | grep -v "Number of cells:" | awk '{sum+=$2} END {print sum}')
    echo "  Number of cells (approx): $CELLS" >> $OUT_FILE
    
    echo "Completed synthesis for $branch_name."
}

# 1. Synthesize current branch (forwarding)
run_synthesis "feature/forwarding"

# 2. Checkout master and synthesize baseline
git checkout -f master
git submodule update --init --recursive --force
run_synthesis "master (baseline)"

# 3. Checkout feature/forwarding back
git checkout -f feature/forwarding
git submodule update --init --recursive --force

echo "Synthesis complete. Results saved to $OUT_FILE."
cat $OUT_FILE
