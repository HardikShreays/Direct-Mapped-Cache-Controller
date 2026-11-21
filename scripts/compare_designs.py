#!/usr/bin/env python3
"""E-3: run the same traces on both designs (direct-mapped vs 2-way LRU),
write results/design_comparison.csv and results/design_comparison.png."""
import csv
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEM = "tb/main_memory_model.v"
TRACES = ["sequential", "random", "loop", "stride", "matmul", "locality"]
RTL = {
    1: [os.path.join("rtl", f) for f in
        ["addr_decode.v", "valid_ram.v", "tag_ram.v", "data_ram.v",
         "cache_controller.v", "cache_top.v"]],
    2: [os.path.join("rtl", f) for f in
        ["addr_decode.v", "valid_ram.v", "tag_ram.v", "data_ram.v", "lru_ram.v",
         "cache_controller_2way.v", "cache_top_2way.v"]],
}
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cache_model import parse_trace, simulate  # noqa: E402

sim_dir = os.path.join(ROOT, "sim")
os.makedirs(sim_dir, exist_ok=True)


def run(binf, trace):
    p = subprocess.run(["vvp", os.path.join("sim", os.path.basename(binf)),
                        f"+trace=traces/{trace}.trace"],
                       cwd=ROOT, capture_output=True, text=True)
    if p.returncode:
        raise RuntimeError(f"vvp failed on {trace}: {p.stdout}{p.stderr}")
    for line in p.stdout.splitlines():
        if line.startswith("TRACE_RESULT"):
            parts = dict(kv.split("=", 1) for kv in line.split()[1:])
            return dict(accesses=int(parts["accesses"]), hits=int(parts["hits"]),
                        misses=int(parts["misses"]), stalls=int(parts["stalls"]))
    raise RuntimeError(f"no TRACE_RESULT for {trace}")


def main():
    bins = {}
    for w in (1, 2):
        binf = os.path.join(sim_dir, f"tb_trace_w{w}")
        cmd = ["iverilog", "-g2012", f"-Ptb_cache_trace.WAYS={w}", "-o", binf,
               *RTL[w], MEM, "tb/tb_cache_trace.v"]
        p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        if p.returncode:
            raise RuntimeError(f"iverilog failed (ways={w}):\n{p.stderr}")
        bins[w] = binf

    rows = []
    for t in TRACES:
        r1 = run(bins[1], t)
        r2 = run(bins[2], t)
        m2 = simulate(parse_trace(os.path.join(ROOT, "traces", f"{t}.trace")),
                      ways=2)
        assert (r2["hits"], r2["misses"]) == (m2.hits, m2.misses), \
            f"2-way model mismatch on {t}"
        rows.append(dict(
            trace=t, accesses=r1["accesses"],
            dm_hits=r1["hits"], dm_hit_rate=f"{r1['hits']/r1['accesses']:.4f}",
            dm_stalls=r1["stalls"],
            tw_hits=r2["hits"], tw_hit_rate=f"{r2['hits']/r2['accesses']:.4f}",
            tw_stalls=r2["stalls"],
            hit_rate_gain=f"{(r2['hits']-r1['hits'])/r1['accesses']:+.4f}"))

    out_csv = os.path.join(ROOT, "results", "design_comparison.csv")
    with open(out_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print("results/design_comparison.csv written")

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib unavailable -- skipping plot", file=sys.stderr)
        return 0

    fig, ax = plt.subplots(figsize=(8, 4.5))
    x = range(len(TRACES))
    dm = [float(r["dm_hit_rate"]) * 100 for r in rows]
    tw = [float(r["tw_hit_rate"]) * 100 for r in rows]
    ax.bar([i - 0.2 for i in x], dm, 0.4, label="direct-mapped", color="#4472c4")
    ax.bar([i + 0.2 for i in x], tw, 0.4, label="2-way LRU", color="#ed7d31")
    ax.set_xticks(list(x))
    ax.set_xticklabels(TRACES)
    ax.set_ylabel("hit rate (%)")
    ax.set_title("Direct-mapped vs 2-way set-associative (1KB, 16B blocks, RTL)")
    ax.grid(True, axis="y", alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(ROOT, "results", "design_comparison.png"), dpi=150)
    plt.close(fig)
    print("results/design_comparison.png written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
