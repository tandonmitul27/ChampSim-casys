#!/usr/bin/env bash
set -euo pipefail

BINARY="./bin/champsim"
SPEC17_DIR="/home/tandonmitul27/workspace/SPEC17"
LOG_DIR="logs/profile"
WARMUP=2000000
SIM=10000000
PARALLEL=32

mkdir -p "$LOG_DIR"

mapfile -t traces < <(ls "$SPEC17_DIR"/*.xz)
total=${#traces[@]}
echo "Found $total traces. Running $PARALLEL at a time..."

completed=0
i=0

while [[ $i -lt $total ]]; do
    pids=()
    batch_traces=()

    # Launch up to PARALLEL jobs
    for (( j=0; j<PARALLEL && i+j<total; j++ )); do
        trace="${traces[$((i+j))]}"
        name=$(basename "$trace")
        log="$LOG_DIR/${name}.log"

        if [[ -f "$log" ]]; then
            echo "Skipping $name (log exists)"
            continue
        fi

        $BINARY -w $WARMUP -i $SIM "$trace" > "$log" 2>&1 &
        pids+=($!)
        batch_traces+=("$name")
    done

    # Wait for batch
    for k in "${!pids[@]}"; do
        if wait "${pids[$k]}"; then
            echo "Done: ${batch_traces[$k]}"
        else
            echo "FAILED: ${batch_traces[$k]}"
        fi
        completed=$((completed + 1))
    done

    echo "Progress: $completed / $total"
    i=$((i + PARALLEL))
done

echo "All traces profiled. Logs in $LOG_DIR/"
