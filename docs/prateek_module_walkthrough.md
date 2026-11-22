# Prateek — 2-Minute Module Explanation (Interview Prep, F-3)

My deliverables are the diagrams, the report, the synthesis run, and the
release verification. Here is how I explain each in two minutes.

## Block diagram

The top level (`cache_top`) splits into three parts: the controller FSM,
three small storage arrays, and the performance counters. The CPU side
issues `cpu_req` with a 32-bit address; the address decoder splits it into
a 22-bit tag, a 6-bit index, and a 4-bit offset. The index picks one of the
64 lines, the tag RAM compares tags, the valid RAM says whether the line is
live, and the data RAM holds the 4-word block. On the memory side the
controller talks word-at-a-time to the behavioral memory model
(`MEM_LATENCY = 10` cycles per access).

## FSM diagram

Four states. **IDLE** waits for `cpu_req` and latches address/we/wdata.
**COMPARE** reads tag and valid at the index; a read hit returns data and
goes to DONE, a read miss goes to REFILL, a write goes to WRITE_THRU.
**REFILL** issues four word reads at the block base, waits `mem_ready` for
each, writes them into the data RAM, then sets valid and tag. Note the
stall counter measured 55 cycles for a miss: 4 words x 10-cycle latency
plus FSM overhead — this is why the report's AMAT analysis shows the cache
only wins when spatial locality reuses the block. **WRITE_THRU** pushes the
write to memory and, on a hit, also updates the cached word; writes never
allocate on a miss (no-write-allocate). **DONE** pulses `cpu_ready` for one
cycle and returns to IDLE.

## Synthesis

Yosys synthesizes `cache_top` with `synth -top cache_top`. The key line in
the log is the memory inference: the 64x32 tag store and 64x128-bit data
store map to block RAM primitives rather than thousands of flip-flops. We
kept the RAMs simple and report the Yosys LUT/FF/memory-bit counts in
`results/synth_resource_table.md`; we state honestly that Vivado numbers
were not run because no FPGA machine was available.

## Release verification

F-2 requires a clean clone to build. I clone the tagged `v1.0` release into
a fresh directory and run `make regress`: all directed tests, both cache
geometries (1KB/16B and 2KB/32B), all five traces with the Python
cross-check matching exactly, and the 2-way conflict tests — ending in
`REGRESSION PASS`.
