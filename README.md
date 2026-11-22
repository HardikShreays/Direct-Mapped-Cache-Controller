# Direct-Mapped Cache Controller

A direct-mapped cache controller in Verilog with a behavioral memory model,
unit + directed + trace-driven testbenches, a Python reference model, exact
counter cross-checking, performance results (hit rates, AMAT, geometry
sweeps), Yosys synthesis, and a 2-way set-associative LRU extension.

**Team:** Hardik Shreyas (lead), Saman, Bhavya, Priyansh, Prateek —
Modern Computer Architecture, Project 6.
**Status:** Phase I + Phase II complete. `make regress` prints
**REGRESSION PASS** (both designs, all traces, exact model cross-check).
**Video:** see [docs/video_link.md](docs/video_link.md).
**Report:** [docs/report/main.pdf](docs/report/main.pdf) (source:
`docs/report/main.tex`).

## Design spec (frozen)

| Parameter      | Value                                        |
|----------------|----------------------------------------------|
| Address width  | 32 bits                                      |
| Cache size     | 1 KB                                         |
| Block size     | 16 bytes (4 words)                           |
| Lines          | 64                                           |
| Address split  | tag [31:10] / index [9:4] / offset [3:0]     |
| Mapping        | Direct-mapped                                |
| Write policy   | Write-through, no-write-allocate             |
| Read miss      | Refill whole block (4 words), then respond   |
| Memory model   | Behavioral, word-wide, MEM_LATENCY = 10/word |
| Hit latency    | 1 cycle after request accepted               |

FSM: `IDLE -> COMPARE -> (REFILL | WRITE_THRU | DONE)`, with `cpu_ready`
pulsing one cycle in DONE. Valid bits clear on reset. Performance counters:
`cnt_access`, `cnt_hit`, `cnt_miss`, `cnt_read`, `cnt_write`,
`cnt_stall_cycles`.

The design is parameterized (`CACHE_BYTES`, `BLOCK_BYTES`; index/offset widths
derived with `$clog2`) and verified at 512B/8B, 1KB/16B, and 2KB/32B.

## Quick start

Prerequisites: Icarus Verilog (`iverilog`, `vvp`), Python 3 with
`numpy`/`pandas`/`matplotlib`, and Yosys (for `make synth`).

```sh
make sim          # directed tests + waveform dump to sim/cache.vcd
make test_units   # per-module self-check testbenches
make test_params  # directed tests at 1KB/16B and 2KB/32B
make trace TRACE=loop   # replay one trace with golden-memory checking

make crosscheck   # RTL counters == cache_model.py on all traces (exact)
make regress      # everything; prints REGRESSION PASS
make results      # regenerate results/*.csv and results/*.png
make synth        # yosys gate-level + memory-inference logs
make clean
```

## What `make regress` runs

1. Unit testbenches for `addr_decode`, `tag_ram`, `valid_ram`, `data_ram`.
2. Directed tests (`tb_cache_basic`): cold miss, hit, conflict miss, spatial
   hits, write miss (no allocate), write hit + read-after-write, mid-run
   reset; plus the same set at 2KB/32B (`tb_cache_params`).
3. Trace-driven tests (`tb_cache_trace`) on six traces for **both designs**
   (direct-mapped and 2-way LRU), with live assertions: `cpu_ready` pulses
   exactly once per request and only in DONE, valid bits are only set on the
   final refill word, and no memory write is ever issued for a read.
4. Conflict-miss regression (`tb_conflict_2way`): a two-block thrash that the
   direct-mapped cache cannot fix (0/24 hits) and 2-way fixes (22/24).
5. Exact cross-check of RTL counters against `scripts/cache_model.py` for
   both designs on all traces.

## Results summary (see `results/`)

- `hit_rates.csv` — RTL hit rates: sequential 75.0%, loop 99.7%, matmul-like
  88.9%, random/stride ~0%, random-with-locality 4.6%.
- `amat.csv` — measured miss penalty 55 cycles (4-word refill over per-word
  handshakes); AMAT 1.18 (loop) to 56.0 (stride) vs. 10 cycles no-cache.
- `sweep_locality.csv` + `hit_rate_vs_*.png` — capacity 1.0%→17.6% for
  256B→4KB on the random-with-locality trace.
- `design_comparison.csv` + `design_comparison.png` — 2-way LRU ties or
  slightly trails direct-mapped on these traces, but eliminates the conflict
  thrash (0/24 → 22/24 hits).
- `write_policy.md` — write-through vs write-back analytic comparison.
- `synth_yosys.log`, `synth_resource_table.md` — Yosys gate-level stats;
  9,664 memory bits detected as BRAM-inferable. No Vivado machine was
  available, so no vendor-tool numbers are claimed.

## Repository layout

```
rtl/                 addr_decode.v tag_ram.v data_ram.v valid_ram.v lru_ram.v
                     cache_controller.v cache_top.v
                     cache_controller_2way.v cache_top_2way.v
tb/                  main_memory_model.v tb_cache_basic.v tb_cache_params.v
                     tb_cache_trace.v tb_conflict_2way.v + unit TBs
traces/              sequential, random, loop, stride, matmul, locality (.trace)
scripts/             gen_traces.py cache_model.py crosscheck.py regress.py
                     run_results.py compare_designs.py
results/             hit_rates.csv amat.csv sweep_locality.csv
                     design_comparison.csv write_policy.md synth logs + plots
docs/                cache_block_diagram.png cache_controller_fsm.png report/ video_link.md
Makefile
```

## Phase II status / remaining team tasks

- [x] Phase A: write path, counters, parameterization (Gates A passed)
- [x] Phase B: trace-driven TB, assertions, cross-check, regression (Gate B)
- [x] Phase C: hit-rate/AMAT/sweep results and plots (Gate C)
- [x] Phase D: Yosys synthesis + resource table (Gate D; Vivado honestly absent)
- [x] Phase E: 2-way set-associative LRU extension on `feature/2way`, merged
      after full regression
- [x] Phase F: final report PDF, this README, tagged release `v1.0`
- [ ] Each member: own contribution paragraph in the report + 2-minute
      explanation of their module (interview prep, Section 8 of the plan)
