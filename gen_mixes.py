#!/usr/bin/env python3
import os
import re
import random

SPEC17_DIR = "/home/tandonmitul27/workspace/SPEC17"
PROFILE_DIR = "logs/profile"
IPC_THRESHOLD = 1.0
NUM_MIXES = 10
TRACES_PER_MIX = 16
SEED = 42

def parse_ipc(log_path):
    with open(log_path) as f:
        for line in f:
            m = re.search(r'Simulation finished.*cumulative IPC: ([0-9.]+)', line)
            if m:
                return float(m.group(1))
    return None

all_traces = sorted([
    os.path.join(SPEC17_DIR, f)
    for f in os.listdir(SPEC17_DIR)
    if f.endswith(".xz")
])

traces = []
skipped = []
for t in all_traces:
    name = os.path.basename(t)
    log = os.path.join(PROFILE_DIR, name + ".log")
    ipc = parse_ipc(log) if os.path.exists(log) else None
    if ipc is not None and ipc >= IPC_THRESHOLD:
        traces.append(t)
    else:
        skipped.append((name, ipc))

print(f"Found {len(all_traces)} traces, {len(traces)} pass IPC >= {IPC_THRESHOLD}, {len(skipped)} filtered out")
if skipped:
    print("Filtered out:")
    for name, ipc in skipped:
        print(f"  {name}: IPC={ipc}")
print()

random.seed(SEED)

for i in range(1, NUM_MIXES + 1):
    mix = random.choices(traces, k=TRACES_PER_MIX)
    filename = f"mix16_{i}"
    with open(filename, "w") as f:
        f.write("\n".join(mix) + "\n")
    print(f"Written {filename}")

print("Done. Run a mix with:")
print("  ./bin/champsim $(cat mix16_1)")
