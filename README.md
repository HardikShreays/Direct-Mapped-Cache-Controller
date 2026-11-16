# Direct-Mapped Cache Controller

A direct-mapped cache controller in Verilog with a behavioral memory model,
directed + unit testbenches, and a Python reference model.

**Team:** Hardik Shreyas (lead), Saman, Bhavya, Priyansh, Prateek —
Modern Computer Architecture, Project 6.
**Status:** Phase I complete (read path, write-through path, waveform, docs).
**Video:** see [docs/video_link.md](docs/video_link.md).

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

## Repository layout

```
rtl/                 addr_decode.v tag_ram.v data_ram.v valid_ram.v
                     cache_controller.v cache_top.v
tb/                  main_memory_model.v tb_cache_basic.v + unit TBs
traces/              sequential, random, loop, stride, matmul (.trace)
scripts/             gen_traces.py cache_model.py make_diagrams.py
docs/                block_diagram.png fsm.png report/ video_link.md
Makefile
```

## Build & run

Requires Icarus Verilog (`iverilog`/`vvp`) and Python 3.

```sh
make sim          # directed tests -> ALL TESTS PASSED + sim/cache.vcd
make test_units   # per-module self-check TBs (decoder + 3 RAMs)
make clean
```

Open `sim/cache.vcd` in GTKWave: the first read misses and refills all four
words (watch `mem_req`/`mem_addr` walk 0x10 -> 0x1C), the next read of the
same block hits with `cpu_ready` in the following cycle.

## Reference-model hit rates (1 KB / 16 B, 10,000 accesses)

```sh
python3 scripts/cache_model.py traces/<name>.trace
```

| Trace      | Hit rate | Sanity check (per plan)      |
|------------|----------|------------------------------|
| sequential | 75.00%   | ~75% (1 miss per 4 words)    |
| random     | 0.12%    | ~0–10%                       |
| loop       | 99.68%   | >95% after warm-up           |
| stride     | 0.00%    | ~0% (new block each access)  |
| matmul     | 88.85%   | high (row reuse)             |

RTL cross-check of counters against the Python model is Phase II (`make
crosscheck`).

## Branch rules

- Branches: `feature/<name>-<task>` (e.g. `feature/saman-rams`), PR into `main`,
  one reviewer who is not the author.
- Commit messages: `<module>: <what>`; small and often.
- Generated files stay out of git except final PNGs/CSVs/report PDF
  (see `.gitignore`).

## Roadmap (Phase II)

- [ ] Trace-driven testbench (`tb_cache_trace.v`) + `make regress`
- [ ] RTL counters cross-checked against `cache_model.py` (`make crosscheck`)
- [ ] Hit-rate CSV/AMAT analysis + size/block sweep plots (`make results`)
- [ ] Yosys synthesis log (`make synth`)
- [ ] Optional: 2-way set-associative extension with LRU (`feature/2way`)
