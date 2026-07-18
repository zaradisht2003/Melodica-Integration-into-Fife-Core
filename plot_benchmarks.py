import matplotlib.pyplot as plt
import numpy as np
import os

benchmarks = ['posit_basic', 'posit_convert', 'posit_dot_product', 'posit_mac_loop', 'posit_matmul', 'posit_poly_eval', 'posit_conv1d', 'posit_iir_filter']
# simplify names for plot
labels = ['basic', 'convert', 'dot_prod', 'mac_loop', 'matmul', 'poly_eval', 'conv1d', 'iir_filter']

# Cycles
cycles_baseline = [172, 157, 348, 3537, 3543, 4065, 718, 2531]
cycles_forward = [169, 157, 359, 3636, 3642, 4062, 733, 2577]
cycles_bp = [166, 157, 361, 808, 1273, 4678, 608, 2203]

# IPC
ipc_baseline = [0.1512, 0.1975, 0.1954, 0.0871, 0.1056, 0.2076, 0.2173, 0.1604]
ipc_forward = [0.1538, 0.1975, 0.1894, 0.0847, 0.1027, 0.2078, 0.2128, 0.1575]
ipc_bp = [0.1566, 0.1975, 0.1884, 0.3812, 0.2938, 0.1804, 0.2566, 0.1843]

x = np.arange(len(labels))
width = 0.25

fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 10))

# Plot 1: Cycles
rects1 = ax1.bar(x - width, cycles_baseline, width, label='Baseline', color='#1f77b4')
rects2 = ax1.bar(x, cycles_forward, width, label='Forwarding', color='#ff7f0e')
rects3 = ax1.bar(x + width, cycles_bp, width, label='Branch Prediction', color='#2ca02c')

ax1.set_ylabel('Execution Cycles')
ax1.set_title('Total Execution Cycles per Benchmark')
ax1.set_xticks(x)
ax1.set_xticklabels(labels)
ax1.legend()
ax1.grid(axis='y', linestyle='--', alpha=0.7)

# Plot 2: IPC
rects4 = ax2.bar(x - width, ipc_baseline, width, label='Baseline', color='#1f77b4')
rects5 = ax2.bar(x, ipc_forward, width, label='Forwarding', color='#ff7f0e')
rects6 = ax2.bar(x + width, ipc_bp, width, label='Branch Prediction', color='#2ca02c')

ax2.set_ylabel('IPC (Instructions Per Cycle)')
ax2.set_title('IPC per Benchmark')
ax2.set_xticks(x)
ax2.set_xticklabels(labels)
ax2.legend()
ax2.grid(axis='y', linestyle='--', alpha=0.7)

fig.tight_layout()

# Save image
os.makedirs('docs', exist_ok=True)
plt.savefig('docs/benchmark_histogram.png', dpi=300)
print("Plot saved to docs/benchmark_histogram.png")
