#!/usr/bin/env python3
"""Measured AMAT from RTL stall cycles (Phase II analysis, Priyansh).

results/amat.csv uses AMAT = hit_time + miss_rate * miss_penalty with one
miss penalty (the 55-cycle read refill) for every miss. Write misses do not
refill: they cost one write-through (~13 cycles), so that formula overstates
the cost on traces with writes.

This script instead uses the RTL's own cnt_stall_cycles (stall_cycles in
results/hit_rates.csv):

    measured_amat = hit_time + stall_cycles / accesses

and compares it with the formula AMAT and the no-cache baseline from
results/amat.csv.

Usage: python3 scripts/analyze.py [--results results]
Writes results/amat_measured.csv. Run `make results` first.
"""
import argparse
import csv
import os
import sys

HIT_TIME = 1.0  # cycles, per the frozen spec


def read_rows(path):
    with open(path, newline="") as f:
        return {r["trace"]: r for r in csv.DictReader(f)}


def analyze(hit_rows, amat_rows):
    """Return one dict per trace with measured vs formula AMAT."""
    out = []
    for trace, h in hit_rows.items():
        if trace not in amat_rows:
            raise KeyError(f"{trace} missing from amat.csv; rerun `make results`")
        a = amat_rows[trace]
        accesses = int(h["accesses"])
        if accesses == 0:
            raise ValueError(f"{trace}: zero accesses")
        stalls_per_access = int(h["stall_cycles"]) / accesses
        measured = HIT_TIME + stalls_per_access
        no_cache = float(a["amat_no_cache_cycles"])
        out.append({
            "trace": trace,
            "hit_rate": f"{float(h['hit_rate']):.4f}",
            "stall_cycles_per_access": f"{stalls_per_access:.2f}",
            "amat_formula_cycles": f"{float(a['amat_cycles']):.2f}",
            "amat_measured_cycles": f"{measured:.2f}",
            "amat_no_cache_cycles": f"{no_cache:.2f}",
            "speedup_measured_vs_no_cache": f"{no_cache / measured:.2f}",
        })
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--results", default="results")
    args = ap.parse_args()
    try:
        rows = analyze(read_rows(os.path.join(args.results, "hit_rates.csv")),
                       read_rows(os.path.join(args.results, "amat.csv")))
    except (OSError, KeyError, ValueError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    path = os.path.join(args.results, "amat_measured.csv")
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    print(f"{'trace':<11}{'hit':>8}{'formula':>9}{'measured':>10}{'no-cache':>10}{'speedup':>9}")
    for r in rows:
        print(f"{r['trace']:<11}{r['hit_rate']:>8}{r['amat_formula_cycles']:>9}"
              f"{r['amat_measured_cycles']:>10}{r['amat_no_cache_cycles']:>10}"
              f"{r['speedup_measured_vs_no_cache']:>9}")
    print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
