#!/usr/bin/env python3
import os
import re
import csv

FREQ_HZ = {
    "mix32": 4100e6,  # xeon_gold
    "mix16": 3400e6,  # xeon_silver
}
LOG_DIRS = {
    "mix32": "logs/mix32",
    "mix16": "logs/mix16",
}
PER_CPU_CSV  = "results_flush_per_cpu.csv"
SUMMARY_CSV  = "results_flush_summary.csv"

def cycles_to_ns(c, freq_hz):
    return round(c / freq_hz * 1e9, 3)

per_cpu_rows = []
summary_rows = []

for mix_type, log_dir in LOG_DIRS.items():
    if not os.path.isdir(log_dir):
        print(f"WARNING: {log_dir} not found, skipping")
        continue

    for fname in sorted(os.listdir(log_dir)):
        if not fname.endswith(".log"):
            continue

        mix_name = fname.replace(".log", "")
        path = os.path.join(log_dir, fname)

        trace_map = {}      # cpu_id -> trace
        l1d_flush  = {}     # cpu_id -> cycles
        l2c_flush  = {}     # cpu_id -> cycles
        max_l1d = max_l2c = llc_flush = total_flush = None

        with open(path) as f:
            for line in f:
                line = line.strip()

                m = re.match(r'CPU (\d+) runs (.+)', line)
                if m:
                    trace_map[int(m.group(1))] = os.path.basename(m.group(2))

                # cpu<N>_L1D FLUSH STALL CYCLES: X
                m = re.match(r'cpu(\d+)_L1D FLUSH STALL CYCLES: (\d+)', line)
                if m:
                    l1d_flush[int(m.group(1))] = int(m.group(2))

                # cpu<N>_L2C FLUSH STALL CYCLES: X
                m = re.match(r'cpu(\d+)_L2C FLUSH STALL CYCLES: (\d+)', line)
                if m:
                    l2c_flush[int(m.group(1))] = int(m.group(2))

                m = re.match(r'L1D MAX FLUSH STALL CYCLES: (\d+)', line)
                if m:
                    max_l1d = int(m.group(1))

                m = re.match(r'L2C MAX FLUSH STALL CYCLES: (\d+)', line)
                if m:
                    max_l2c = int(m.group(1))

                m = re.match(r'LLC FLUSH STALL CYCLES: (\d+)', line)
                if m:
                    llc_flush = int(m.group(1))

                m = re.match(r'TOTAL WRITEBACK FLUSH TIME: (\d+) cycles', line)
                if m:
                    total_flush = int(m.group(1))

        # Per-CPU rows (union of CPUs seen in either cache)
        freq = FREQ_HZ[mix_type]
        all_cpus = sorted(set(l1d_flush) | set(l2c_flush))
        for cpu in all_cpus:
            l1d_c = l1d_flush.get(cpu, 0)
            l2c_c = l2c_flush.get(cpu, 0)
            per_cpu_rows.append({
                "mix_type":               mix_type,
                "mix":                    mix_name,
                "cpu":                    cpu,
                "trace":                  trace_map.get(cpu, "unknown"),
                "l1d_flush_stall_cycles": l1d_c,
                "l1d_flush_stall_ns":     cycles_to_ns(l1d_c, freq),
                "l2c_flush_stall_cycles": l2c_c,
                "l2c_flush_stall_ns":     cycles_to_ns(l2c_c, freq),
            })

        # Summary row
        summary_rows.append({
            "mix_type":             mix_type,
            "mix":                  mix_name,
            "max_l1d_flush_cycles": max_l1d,
            "max_l1d_flush_ns":     cycles_to_ns(max_l1d, freq) if max_l1d is not None else "",
            "max_l2c_flush_cycles": max_l2c,
            "max_l2c_flush_ns":     cycles_to_ns(max_l2c, freq) if max_l2c is not None else "",
            "llc_flush_cycles":     llc_flush,
            "llc_flush_ns":         cycles_to_ns(llc_flush, freq) if llc_flush is not None else "",
            "total_flush_cycles":   total_flush,
            "total_flush_ns":       cycles_to_ns(total_flush, freq) if total_flush is not None else "",
        })

with open(PER_CPU_CSV, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=[
        "mix_type", "mix", "cpu", "trace",
        "l1d_flush_stall_cycles", "l1d_flush_stall_ns",
        "l2c_flush_stall_cycles", "l2c_flush_stall_ns",
    ])
    writer.writeheader()
    writer.writerows(per_cpu_rows)

with open(SUMMARY_CSV, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=[
        "mix_type", "mix",
        "max_l1d_flush_cycles", "max_l1d_flush_ns",
        "max_l2c_flush_cycles", "max_l2c_flush_ns",
        "llc_flush_cycles",     "llc_flush_ns",
        "total_flush_cycles",   "total_flush_ns",
    ])
    writer.writeheader()
    writer.writerows(summary_rows)

print(f"Written {len(per_cpu_rows)} rows to {PER_CPU_CSV}")
print(f"Written {len(summary_rows)} rows to {SUMMARY_CSV}")
