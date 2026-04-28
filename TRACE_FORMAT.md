# SPM-Tagged Trace Format & ChampSim Adaptation Notes

## What Changed in the Traces

Standard ChampSim traces use a 64-byte `input_instr` record. These traces use an
**extended 72-byte record** with two extra arrays appended at the end:

```
Offset  Size  Field
------  ----  -----
0       8     ip  (instruction pointer)
8       1     is_branch
9       1     branch_taken
10      2     destination_registers[2]
12      4     source_registers[4]
16      16    destination_memory[2]   (2 x uint64 addresses)
32      32    source_memory[4]        (4 x uint64 addresses)
--- NEW ---
64      2     destination_mem_type[2] (one byte per destination memory operand)
66      4     source_mem_type[4]      (one byte per source memory operand)
70      2     (padding to reach 72-byte alignment)
```

### mem_type encoding
- `0` = DRAM-direct  — goes through the normal cache hierarchy
- `1` = SPM-managed  — pre-loaded into the scratchpad; always a hit, no DRAM fetch

The SPM-managed regions in these traces are:
- **Weight matrix W** (64 MB, F32, shape K×N = 4096×4096)
- **Input activation** (512 KB for GEMM M=32; 16 KB for GEMV M=1)

~62% of all instructions in both traces touch an SPM-managed address.

---

## How to Adapt ChampSim

### 1. Update the trace reader

ChampSim's trace reader currently expects 64-byte records. Change it to read 72 bytes
and populate the `mem_type` fields into whatever instruction struct ChampSim uses
internally (add two arrays mirroring the trace layout).

Key file to change: wherever `input_instr` is read from the trace file, increase the
read size from `sizeof(input_instr_old)` = 64 to 72.

### 2. Tag memory requests with their region type

When ChampSim issues a memory request (load or store), attach the `mem_type` bit from
the trace to the request packet. This tells downstream components whether the access
targets the SPM or DRAM.

### 3. Model the SPM at the LLC level

The proposed memory hierarchy removes L1/L2 caches and replaces the LLC with an SPM:

```
CPU core
  └─ (no L1/L2 cache)
       └─ SPM  (replaces LLC)
            └─ DRAM
```

SPM behavior for a memory request:
- If `mem_type == 1` (SPM-managed): return immediately with SPM hit latency.
  No DRAM fetch. The block is assumed pre-loaded.
- If `mem_type == 0` (DRAM-direct): go straight to DRAM with full DRAM latency.
  No caching in the SPM on the way back.

In ChampSim terms, intercept memory requests at the LLC (or wherever the memory
controller hands off to DRAM) and short-circuit SPM-tagged accesses:

```cpp
// Pseudocode for the SPM model in ChampSim
void handle_memory_request(MemRequest& req) {
    if (req.mem_type == 1) {
        // SPM hit — respond with spm_latency, no DRAM access
        complete_request(req, SPM_LATENCY_CYCLES);
    } else {
        // DRAM-direct — full DRAM latency
        send_to_dram(req);
    }
}
```

Suggested latency values to start with:
- `SPM_LATENCY_CYCLES`: 10–30 cycles (similar to SRAM, sized to fit weights)
- DRAM latency: keep ChampSim's existing DRAM model unchanged

### 4. Disable or bypass L1/L2 for the experiment

To isolate the SPM model, either:
- Set L1/L2 cache sizes to 0 (if ChampSim supports it), or
- Make all L1/L2 lookups always miss so every access reaches the SPM/DRAM stage

---

## Trace Stats

| Trace                    | Records | SPM-tagged | DRAM-only | Compressed |
|--------------------------|---------|------------|-----------|------------|
| bench_gemm_f32.trace.xz  | 10 M    | 61.7 %     | 38.3 %    | 1.3 MB     |
| bench_gemv_f32.trace.xz  | 10 M    | 61.4 %     | 38.6 %    | 2.6 MB     |

Captured from: F32×F32 GEMM/GEMV, M=32/1, N=K=4096, single-threaded, inside the
benchmark loop only (between `BENCH_GEMM_START` and `BENCH_GEMM_END` markers).
