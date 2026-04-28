#!/usr/bin/env bash
set -euo pipefail

CHAMPSIM_DIR="/home/tandonmitul27/workspace/champsim-spmB2/ChampSim-casys"
LOGS_DIR="${CHAMPSIM_DIR}/logs"
WARMUP=50000000
SIM=200000000
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

mkdir -p "${LOGS_DIR}"

cd "${CHAMPSIM_DIR}"

pids=()
log_files=()
labels=()

run_sim() {
    local label="$1"
    local log_file="${LOGS_DIR}/${TIMESTAMP}_${label}.log"
    shift
    log_files+=("${log_file}")
    labels+=("${label}")
    echo "[$(date +%T)] Launching: ${label} -> ${log_file}"
    "$@" > "${log_file}" 2>&1 &
    pids+=($!)
}

# xeon_gold simulations (32 threads)
run_sim "xeon_gold_spmB2_gemm_q4k_M16_K4096_N128256_spm" \
    bin/xeon_gold_spmB2 \
    --warmup-instructions ${WARMUP} --simulation-instructions ${SIM} \
    $(python3 -c "print(' '.join(['traces/bench_gemm_q4k_M16_K4096_N128256_spm.trace.xz']*32))")

run_sim "xeon_gold_spmB2_gemm_q4k_M16_K14336_N4096_spm" \
    bin/xeon_gold_spmB2 \
    --warmup-instructions ${WARMUP} --simulation-instructions ${SIM} \
    $(python3 -c "print(' '.join(['traces/bench_gemm_q4k_M16_K14336_N4096_spm.trace.xz']*32))")

run_sim "xeon_gold_spmB2_gemv_q4k_4096x128256_spm" \
    bin/xeon_gold_spmB2 \
    --warmup-instructions ${WARMUP} --simulation-instructions ${SIM} \
    $(python3 -c "print(' '.join(['traces/bench_gemv_q4k_4096x128256_spm.trace.xz']*32))")

run_sim "xeon_gold_spmB2_gemv_q4k_14336x4096_spm" \
    bin/xeon_gold_spmB2 \
    --warmup-instructions ${WARMUP} --simulation-instructions ${SIM} \
    $(python3 -c "print(' '.join(['traces/bench_gemv_q4k_14336x4096_spm.trace.xz']*32))")

# xeon_silver simulations (16 threads)
run_sim "xeon_silver_spmB2_gemm_q4k_M16_K4096_N128256_spm" \
    bin/xeon_silver_spmB2 \
    --warmup-instructions ${WARMUP} --simulation-instructions ${SIM} \
    $(python3 -c "print(' '.join(['traces/bench_gemm_q4k_M16_K4096_N128256_spm.trace.xz']*16))")

run_sim "xeon_silver_spmB2_gemm_q4k_M16_K14336_N4096_spm" \
    bin/xeon_silver_spmB2 \
    --warmup-instructions ${WARMUP} --simulation-instructions ${SIM} \
    $(python3 -c "print(' '.join(['traces/bench_gemm_q4k_M16_K14336_N4096_spm.trace.xz']*16))")

run_sim "xeon_silver_spmB2_gemv_q4k_4096x128256_spm" \
    bin/xeon_silver_spmB2 \
    --warmup-instructions ${WARMUP} --simulation-instructions ${SIM} \
    $(python3 -c "print(' '.join(['traces/bench_gemv_q4k_4096x128256_spm.trace.xz']*16))")

run_sim "xeon_silver_spmB2_gemv_q4k_14336x4096_spm" \
    bin/xeon_silver_spmB2 \
    --warmup-instructions ${WARMUP} --simulation-instructions ${SIM} \
    $(python3 -c "print(' '.join(['traces/bench_gemv_q4k_14336x4096_spm.trace.xz']*16))")

echo ""
echo "All 8 simulations launched. Waiting for completion..."
echo ""

# Wait for each PID and collect exit codes
failed=0
for i in "${!pids[@]}"; do
    pid="${pids[$i]}"
    label="${labels[$i]}"
    log="${log_files[$i]}"
    if wait "${pid}"; then
        echo "[$(date +%T)] DONE   ${label}"
    else
        echo "[$(date +%T)] FAILED ${label} (exit $?) -- see ${log}"
        failed=$((failed + 1))
    fi
done

echo ""
if [ "${failed}" -eq 0 ]; then
    echo "All simulations completed successfully."
    echo "Logs saved to: ${LOGS_DIR}/"
else
    echo "${failed} simulation(s) failed. Check logs in ${LOGS_DIR}/"
    exit 1
fi
