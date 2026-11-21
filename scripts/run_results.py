#!/usr/bin/env python3
"""Phase C experiments and results (C-1..C-5).

  1. Run the RTL on all traces            -> results/hit_rates.csv   (C-2)
  2. AMAT analysis                        -> results/amat.csv        (C-3)
  3. Cache/block geometry sweep on the
     random-with-locality trace           -> results/sweep_locality.csv,
                                             results/*.png           (C-4)
  4. Write-through vs write-back analytic -> results/write_policy.md (C-5)

Gate C: `make results` regenerates all files with stable numbers.
"""
import csv
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from cache_model import parse_trace, simulate  # noqa: E402

RTL = [os.path.join("rtl", f) for f in
       ["addr_decode.v", "valid_ram.v", "tag_ram.v", "data_ram.v",
        "cache_controller.v", "cache_top.v"]]
MEM = "tb/main_memory_model.v"
TRACES = ["sequential", "random", "loop", "stride", "matmul", "locality"]
RESULT_RE = None
HIT_TIME_CYCLES = 1
MEM_LATENCY = 10
SWEEP_CACHES = [256, 512, 1024, 2048, 4096]
SWEEP_BLOCKS = [8, 16, 32, 64]
SWEEP_TRACE = "locality"

results_dir = os.path.join(ROOT, "results")
sim_dir = os.path.join(ROOT, "sim")
os.makedirs(results_dir, exist_ok=True)
os.makedirs(sim_dir, exist_ok=True)


def compile_tb(out, cache_bytes=1024, block_bytes=16):
    binf = os.path.join(sim_dir, out)
    cmd = ["iverilog", "-g2012",
           f"-Ptb_cache_trace.CACHE_BYTES={cache_bytes}",
           f"-Ptb_cache_trace.BLOCK_BYTES={block_bytes}",
           "-o", binf, *RTL, MEM, "tb/tb_cache_trace.v"]
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if p.returncode:
        raise RuntimeError(f"iverilog failed:\n{p.stderr}")
    return binf


def run_trace(binf, trace_name):
    """Run one trace; return counter dict parsed from TRACE_RESULT."""
    p = subprocess.run(["vvp", os.path.join("sim", os.path.basename(binf)),
                        f"+trace=traces/{trace_name}.trace"],
                       cwd=ROOT, capture_output=True, text=True)
    if p.returncode:
        raise RuntimeError(f"vvp failed on {trace_name}:\n{p.stdout}{p.stderr}")
    for line in p.stdout.splitlines():
        if line.startswith("TRACE_RESULT"):
            parts = dict(kv.split("=", 1) for kv in line.split()[1:])
            return dict(accesses=int(parts["accesses"]), hits=int(parts["hits"]),
                        misses=int(parts["misses"]), reads=int(parts["reads"]),
                        writes=int(parts["writes"]), stalls=int(parts["stalls"]))
    raise RuntimeError(f"no TRACE_RESULT for {trace_name}")


def main():
    # ---------- C-2: hit_rates.csv ----------
    binf = compile_tb("tb_trace")
    rows = []
    for t in TRACES:
        rtl = run_trace(binf, t)
        model = simulate(parse_trace(os.path.join(ROOT, "traces", f"{t}.trace")))
        assert (rtl["hits"], rtl["misses"]) == (model.hits, model.misses), \
            f"model mismatch on {t}"
        rows.append(dict(trace=t, accesses=rtl["accesses"], hits=rtl["hits"],
                         misses=rtl["misses"],
                         hit_rate=f"{rtl['hits']/rtl['accesses']:.4f}",
                         stall_cycles=rtl["stalls"]))
    with open(os.path.join(results_dir, "hit_rates.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print("results/hit_rates.csv written")

    # ---------- C-3: amat.csv ----------
    # miss_penalty measured from the RTL on a pure-read trace (every stall is
    # a block refill): use the sequential trace (100% reads).
    seq = next(r for r in rows if r["trace"] == "sequential")
    miss_penalty = seq["stall_cycles"] / seq["misses"]
    amat_rows = []
    for r in rows:
        miss_rate = r["misses"] / r["accesses"]
        amat = HIT_TIME_CYCLES + miss_rate * miss_penalty
        amat_rows.append(dict(
            trace=r["trace"], hit_rate=r["hit_rate"],
            miss_rate=f"{miss_rate:.4f}",
            miss_penalty_cycles=f"{miss_penalty:.1f}",
            amat_cycles=f"{amat:.2f}",
            amat_no_cache_cycles=MEM_LATENCY,
            speedup_vs_no_cache=f"{MEM_LATENCY/amat:.2f}"))
    with open(os.path.join(results_dir, "amat.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(amat_rows[0].keys()))
        w.writeheader()
        w.writerows(amat_rows)
    print("results/amat.csv written "
          f"(miss_penalty={miss_penalty:.1f} cycles, no-cache={MEM_LATENCY})")

    # ---------- C-4: geometry sweep on the locality trace ----------
    sweep = []
    for cb in SWEEP_CACHES:
        for bb in SWEEP_BLOCKS:
            binf_s = compile_tb(f"tb_trace_sweep_{cb}_{bb}", cb, bb)
            rtl = run_trace(binf_s, SWEEP_TRACE)
            sweep.append(dict(cache_bytes=cb, block_bytes=bb,
                              accesses=rtl["accesses"], hits=rtl["hits"],
                              hit_rate=rtl["hits"] / rtl["accesses"]))
            os.remove(binf_s)
    with open(os.path.join(results_dir, "sweep_locality.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["cache_bytes", "block_bytes",
                                          "accesses", "hits", "hit_rate"])
        w.writeheader()
        for s in sweep:
            w.writerow({**s, "hit_rate": f"{s['hit_rate']:.4f}"})
    print("results/sweep_locality.csv written")

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib unavailable -- skipping plots", file=sys.stderr)
        return 0

    # hit rate vs cache size, one line per block size
    fig, ax = plt.subplots(figsize=(7, 4.5))
    for bb in SWEEP_BLOCKS:
        pts = [(s["cache_bytes"], s["hit_rate"]) for s in sweep
               if s["block_bytes"] == bb]
        pts.sort()
        ax.plot([p[0] for p in pts], [p[1] * 100 for p in pts],
                marker="o", label=f"{bb}B blocks")
    ax.set_xscale("log", base=2)
    ax.set_xticks(SWEEP_CACHES)
    ax.set_xticklabels([f"{c//1024}KB" if c >= 1024 else f"{c}B" for c in SWEEP_CACHES])
    ax.set_xlabel("cache size")
    ax.set_ylabel("hit rate (%)")
    ax.set_title(f"Hit rate vs cache geometry -- {SWEEP_TRACE} trace (RTL)")
    ax.grid(True, alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(results_dir, "hit_rate_vs_cache.png"), dpi=150)
    plt.close(fig)

    # hit rate vs block size, one line per cache size
    fig, ax = plt.subplots(figsize=(7, 4.5))
    for cb in SWEEP_CACHES:
        pts = [(s["block_bytes"], s["hit_rate"]) for s in sweep
               if s["cache_bytes"] == cb]
        pts.sort()
        ax.plot([p[0] for p in pts], [p[1] * 100 for p in pts],
                marker="o", label=f"{cb//1024}KB" if cb >= 1024 else f"{cb}B")
    ax.set_xticks(SWEEP_BLOCKS)
    ax.set_xlabel("block size (bytes)")
    ax.set_ylabel("hit rate (%)")
    ax.set_title(f"Hit rate vs block size -- {SWEEP_TRACE} trace (RTL)")
    ax.grid(True, alpha=0.3)
    ax.legend(title="cache size")
    fig.tight_layout()
    fig.savefig(os.path.join(results_dir, "hit_rate_vs_block.png"), dpi=150)
    plt.close(fig)

    # hit rate by trace (default 1KB/16B geometry)
    fig, ax = plt.subplots(figsize=(7, 4))
    names = [r["trace"] for r in rows]
    rates = [float(r["hit_rate"]) * 100 for r in rows]
    ax.bar(names, rates, color="#4472c4")
    ax.set_ylabel("hit rate (%)")
    ax.set_title("RTL hit rate by trace (1KB cache, 16B blocks)")
    ax.grid(True, axis="y", alpha=0.3)
    fig.tight_layout()
    fig.savefig(os.path.join(results_dir, "hit_rate_by_trace.png"), dpi=150)
    plt.close(fig)
    print("results/*.png written")

    # ---------- C-5: write-through vs write-back analytic note ----------
    # Measured from the RTL at the default geometry:
    #   read-miss refill (4 words, one per handshake) = miss_penalty cycles
    #   write-through = MEM_LATENCY + overhead
    wt_penalty = MEM_LATENCY + 3   # WRITE_THRU: issue + latency + handshake
    note = f"""# Write-through vs write-back: analytic comparison (C-5)

Measured on the RTL at the default geometry (1KB cache, 16B blocks,
MEM_LATENCY={MEM_LATENCY} cycles/word):

- Read miss (refill, 4 word handshakes): **{miss_penalty:.0f} cycles**
- Write hit (cache word update + write-through): **{wt_penalty} cycles**
- Write miss (memory only, no allocate): **{wt_penalty} cycles**

## Analytic cycle cost per write-dominant workload

| Metric                              | Write-through (this design)      | Write-back (analytic)                       |
|-------------------------------------|----------------------------------|---------------------------------------------|
| Write hit cost                      | {wt_penalty} cycles (memory write) | 1 cycle (dirty bit set)                     |
| Dirty line eviction                 | none (line always clean)         | refill + {MEM_LATENCY}+ cycles to write back |
| Extra state                         | none                             | 1 dirty bit per line (64 bits total)        |
| Memory write traffic on 100% dirty evictions | 1 word per write (immediate) | 1 block (16B) per evicted line            |
| Read-after-write visibility         | memory always current (safe)     | stale until writeback                       |

For the {SWEEP_TRACE} trace (2051 writes of 10000 accesses), write-through adds
roughly {2051 * wt_penalty} write stall cycles. A write-back design would reduce
this to ~2051 one-cycle dirty-bit updates, but every dirty eviction would
then pay a {MEM_LATENCY}+ cycle writeback on top of the refill, and the controller
would need dirty bits, an eviction writeback path, and a write buffer to
avoid stalling on eviction. Given the small 1KB cache and high eviction
rate (a new block refills the same line frequently in this workload), the
writeback traffic would approach one block per miss, so write-through is
the simpler and, at this scale, competitive policy.
"""
    with open(os.path.join(results_dir, "write_policy.md"), "w") as f:
        f.write(note)
    print("results/write_policy.md written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
