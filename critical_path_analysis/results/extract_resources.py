import os
import glob
import re

log_files = glob.glob('*.log')

results = {}

for log_file in log_files:
    with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        
    # Find the last "Printing statistics."
    stat_idx = content.rfind("Printing statistics.")
    if stat_idx == -1:
        print(f"Could not find statistics in {log_file}")
        continue
        
    stat_text = content[stat_idx:]
    
    # We want only the first module stats after the LAST "Printing statistics." 
    # Usually it's the top module. Let's just find "=== ... ===" and parse until the next "==="
    
    # Extract overall metrics
    wires = re.search(r'Number of wires:\s+(\d+)', stat_text)
    cells = re.search(r'Number of cells:\s+(\d+)', stat_text)
    
    # Extract cell breakdown
    cell_breakdown = {}
    lines = stat_text.split('\n')
    in_cells = False
    for line in lines:
        if 'Number of cells:' in line:
            in_cells = True
            continue
        if in_cells:
            # Match lines like "     $_AND_                       1260"
            match = re.match(r'\s+(\S+)\s+(\d+)', line)
            if match and line.startswith('    '):
                cell_name = match.group(1)
                count = int(match.group(2))
                cell_breakdown[cell_name] = cell_breakdown.get(cell_name, 0) + count
            elif not line.startswith(' ') and line.strip() != '' and not line.startswith('='):
                # We reached a line that doesn't start with space, maybe the end of the list
                pass
                
    results[log_file] = {
        'wires': wires.group(1) if wires else '0',
        'cells': cells.group(1) if cells else '0',
        'breakdown': cell_breakdown
    }

print("| Design | Wires | Total Cells | DFFs (Flops) | MUXes | Logic Gates |")
print("|--------|-------|-------------|--------------|-------|-------------|")

for log_file, data in sorted(results.items()):
    design_name = log_file.replace('.log', '')
    wires = data['wires']
    total_cells = data['cells']
    
    dffs = 0
    muxes = 0
    logic = 0
    
    for cell, count in data['breakdown'].items():
        if 'DFF' in cell or 'dff' in cell.lower():
            dffs += count
        elif 'MUX' in cell or 'mux' in cell.lower():
            muxes += count
        else:
            logic += count
            
    print(f"| {design_name} | {wires} | {total_cells} | {dffs} | {muxes} | {logic} |")
