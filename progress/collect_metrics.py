#!/usr/bin/env python3
"""
collect_metrics.py
Parse a Fife simulation log.txt and extract performance metrics.
Usage: python3 collect_metrics.py <log.txt>
"""

import sys
import re

def parse_log(filename):
    retired = 0
    stalls = 0
    max_cycle = 0
    min_cycle = None
    first_ret_cycle = None
    last_ret_cycle = None
    retired_instrs = set()  # (inum) to avoid double-counting

    try:
        with open(filename) as f:
            for line in f:
                m = re.match(r'Trace\s+(\d+)\s+(\d+)\s+([0-9a-f]+)\s+([0-9a-f]+)\s+(\S+)', line)
                if not m:
                    continue
                cycle = int(m.group(1))
                inum  = int(m.group(2))
                stage = m.group(5)

                max_cycle = max(max_cycle, cycle)
                if min_cycle is None or cycle < min_cycle:
                    min_cycle = cycle

                if stage.startswith('RET.'):
                    if inum not in retired_instrs:
                        retired_instrs.add(inum)
                        retired += 1
                    if first_ret_cycle is None:
                        first_ret_cycle = cycle
                    last_ret_cycle = cycle

                elif stage == 'RR.S':
                    stalls += 1
    except FileNotFoundError:
        return None

    total_cycles = (last_ret_cycle - (first_ret_cycle or 0) + 1) if last_ret_cycle else max_cycle
    ipc = retired / max(1, total_cycles)
    stall_rate = stalls / max(1, stalls + retired)

    return {
        'retired': retired,
        'stalls': stalls,
        'first_ret_cycle': first_ret_cycle,
        'last_ret_cycle': last_ret_cycle,
        'active_cycles': total_cycles,
        'ipc': ipc,
        'stall_rate': stall_rate,
    }

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 collect_metrics.py <log.txt>")
        sys.exit(1)
    r = parse_log(sys.argv[1])
    if r is None:
        print("ERROR: could not parse log file")
        sys.exit(1)
    print(f"Retired instructions : {r['retired']}")
    print(f"Stall cycles         : {r['stalls']}")
    print(f"Active cycles        : {r['active_cycles']}")
    print(f"IPC                  : {r['ipc']:.4f}")
    print(f"Stall rate           : {r['stall_rate']:.4f}  ({r['stall_rate']*100:.1f}%)")
