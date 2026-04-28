#!/usr/bin/env bash
set -euo pipefail

BINARY="./bin/xeon_gold"
WARMUP_INSTRUCTIONS=50000000
SIM_INSTRUCTIONS=200000000
NUM_MIXES=10
LOG_DIR="logs/mix32"

mkdir -p "$LOG_DIR"

pids=()

for i in $(seq 1 $NUM_MIXES); do
    mix_file="mix32/mix32_${i}"
    log_file="${LOG_DIR}/mix32_${i}.log"

    if [[ ! -f "$mix_file" ]]; then
        echo "WARNING: $mix_file not found, skipping"
        continue
    fi

    echo "Starting mix $i -> $log_file"
    $BINARY \
        -w $WARMUP_INSTRUCTIONS \
        -i $SIM_INSTRUCTIONS \
        $(cat "$mix_file") \
        > "$log_file" 2>&1 &

    pids+=($!)
done

echo "Launched ${#pids[@]} simulations (PIDs: ${pids[*]})"
echo "Waiting for all to complete..."

failed=0
for i in "${!pids[@]}"; do
    mix_num=$((i + 1))
    if wait "${pids[$i]}"; then
        echo "mix32_${mix_num} done"
    else
        echo "mix32_${mix_num} FAILED (exit code $?)"
        failed=$((failed + 1))
    fi
done

if [[ $failed -eq 0 ]]; then
    echo "All simulations completed successfully. Logs in $LOG_DIR/"
else
    echo "$failed simulation(s) failed. Check logs in $LOG_DIR/"
    exit 1
fi
