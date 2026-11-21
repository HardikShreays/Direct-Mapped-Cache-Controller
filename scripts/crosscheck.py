#!/usr/bin/env python3
"""Cross-check RTL counters against the Python reference model (B-3).

For every trace in traces/, runs the trace-driven testbench
(tb_cache_trace.v) through Icarus Verilog and compares hits, misses, reads,
writes and accesses against scripts/cache_model.py. Exits non-zero on any
mismatch, printing the first differing field.

Usage:
    python3 scripts/crosscheck.py [--traces traces] [--cache-bytes 1024]
                                  [--block-bytes 16] [--keep-out]
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from cache_model import parse_trace, simulate  # noqa: E402

RTL = {
    1: ["addr_decode.v", "valid_ram.v", "tag_ram.v", "data_ram.v",
        "cache_controller.v", "cache_top.v"],
    2: ["addr_decode.v", "valid_ram.v", "tag_ram.v", "data_ram.v", "lru_ram.v",
        "cache_controller_2way.v", "cache_top_2way.v"],
}
RESULT_RE = re.compile(
    r"TRACE_RESULT trace=(\S+) accesses=(\d+) hits=(\d+) misses=(\d+) "
    r"reads=(\d+) writes=(\d+) stalls=(\d+)")


def run_rtl(trace_path, cache_bytes, block_bytes, ways, sim_bin, workdir):
    """Compile+run the trace tb; return the counters dict or raise."""
    iver = subprocess.run(["iverilog", "-g2012",
                           f"-Ptb_cache_trace.WAYS={ways}",
                           f"-Ptb_cache_trace.CACHE_BYTES={cache_bytes}",
                           f"-Ptb_cache_trace.BLOCK_BYTES={block_bytes}",
                           "-o", sim_bin]
                          + [os.path.join(ROOT, "rtl", f) for f in RTL[ways]]
                          + [os.path.join(ROOT, "tb", "main_memory_model.v"),
                             os.path.join(ROOT, "tb", "tb_cache_trace.v")],
                          capture_output=True, text=True)
    if iver.returncode:
        raise RuntimeError(f"iverilog failed:\n{iver.stderr}")
    vp = subprocess.run(["vvp", os.path.relpath(sim_bin), f"+trace={os.path.relpath(trace_path)}"],
                        capture_output=True, text=True, cwd=ROOT)
    if vp.returncode:
        raise RuntimeError(f"vvp failed on {trace_path}:\n{vp.stdout}{vp.stderr}")
    m = RESULT_RE.search(vp.stdout)
    if not m:
        raise RuntimeError(f"no TRACE_RESULT line for {trace_path}:\n{vp.stdout}")
    _, acc, hits, misses, reads, writes, _stalls = m.groups()
    return dict(accesses=int(acc), hits=int(hits), misses=int(misses),
                reads=int(reads), writes=int(writes))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--traces", default=os.path.join(ROOT, "traces"))
    ap.add_argument("--cache-bytes", type=int, default=1024)
    ap.add_argument("--block-bytes", type=int, default=16)
    ap.add_argument("--ways", type=int, default=1, choices=(1, 2))
    args = ap.parse_args(argv)

    workdir = os.path.join(ROOT, "sim")
    os.makedirs(workdir, exist_ok=True)
    sim_bin = os.path.join(workdir, "tb_trace_cross")
    trace_files = sorted(f for f in os.listdir(args.traces) if f.endswith(".trace"))
    if not trace_files:
        print(f"error: no .trace files in {args.traces}", file=sys.stderr)
        return 1

    failures = 0
    for tf in trace_files:
        path = os.path.join(args.traces, tf)
        model = simulate(parse_trace(path), args.cache_bytes, args.block_bytes,
                         args.ways)
        rtl = run_rtl(path, args.cache_bytes, args.block_bytes, args.ways,
                      sim_bin, workdir)
        exp = dict(accesses=model.accesses, hits=model.hits, misses=model.misses,
                   reads=model.reads, writes=model.writes)
        bad = [k for k in exp if exp[k] != rtl[k]]
        if bad:
            failures += 1
            print(f"CROSSCHECK FAIL {tf}: " +
                  ", ".join(f"{k} rtl={rtl[k]} model={exp[k]}" for k in bad))
        else:
            print(f"CROSSCHECK PASS {tf}: hits={rtl['hits']} "
                  f"misses={rtl['misses']} of {rtl['accesses']}")

    os.remove(sim_bin)
    if failures:
        print(f"crosscheck: {failures} trace(s) FAILED")
        return 1
    print("CROSSCHECK OK: RTL counters == cache_model.py on all traces")
    return 0


if __name__ == "__main__":
    sys.exit(main())
