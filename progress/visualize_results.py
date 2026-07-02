import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import os

def create_grouped_bar_chart(df_base, df_fwd, metric, title, ylabel, filename):
    # Ensure both dataframes have the same tests
    tests = df_base['test'].tolist()
    
    # Extract data for the metric
    base_data = df_base[metric].tolist()
    fwd_data = df_fwd[metric].tolist()
    
    x = np.arange(len(tests))
    width = 0.35  # width of the bars
    
    fig, ax = plt.subplots(figsize=(12, 6))
    rects1 = ax.bar(x - width/2, base_data, width, label='Baseline', color='lightcoral')
    rects2 = ax.bar(x + width/2, fwd_data, width, label='Forwarding', color='skyblue')
    
    # Add some text for labels, title and custom x-axis tick labels, etc.
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.set_xticks(x)
    ax.set_xticklabels(tests, rotation=45, ha='right')
    ax.legend()
    
    fig.tight_layout()
    plt.savefig(filename, dpi=300, bbox_inches='tight')
    plt.close()

def main():
    base_file = 'benchmark_results_baseline.csv'
    fwd_file = 'benchmark_results_forwarding.csv'
    
    if not os.path.exists(base_file) or not os.path.exists(fwd_file):
        print(f"Error: Missing CSV files. Make sure {base_file} and {fwd_file} exist.")
        return
        
    df_base = pd.read_csv(base_file)
    df_fwd = pd.read_csv(fwd_file)
    
    # Create docs/images directory if it doesn't exist
    os.makedirs('../docs/images', exist_ok=True)
    
    # 1. IPC Comparison
    create_grouped_bar_chart(
        df_base, df_fwd, 
        metric='ipc', 
        title='IPC Comparison (Baseline vs Forwarding)', 
        ylabel='Instructions Per Cycle (IPC)', 
        filename='../docs/images/ipc_comparison.png'
    )
    
    # 2. Stall Rate Comparison
    create_grouped_bar_chart(
        df_base, df_fwd, 
        metric='stall_rate_pct', 
        title='Stall Rate % Comparison (Baseline vs Forwarding)', 
        ylabel='Stall Rate (%)', 
        filename='../docs/images/stall_rate_comparison.png'
    )
    
    # 3. Active Cycles Comparison
    create_grouped_bar_chart(
        df_base, df_fwd, 
        metric='active_cycles', 
        title='Total Active Cycles Comparison (Baseline vs Forwarding)', 
        ylabel='Active Cycles', 
        filename='../docs/images/active_cycles_comparison.png'
    )
    
    print("Visualizations generated successfully in ../docs/images/")

if __name__ == "__main__":
    main()
