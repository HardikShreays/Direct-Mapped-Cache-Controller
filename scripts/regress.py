#!/usr/bin/env python3
"""Full regression (Gate B): unit TBs, directed TB, parameterized directed
TBs, all traces through tb_cache_trace, and the model crosscheck.

Prints REGRESSION PASS and exits 0 when everything passes.
"""
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

sim = os.path.join(ROOT, "sim")
os.makedirs(sim, exist_ok=True)
failures = []


def run_sim(binf, label, expect_substr=None):
    p = subprocess.run(["vvp", binf], cwd=ROOT, capture_output=True, text=True)
    out = p.stdout + p.stderr
    if p.returncode != 0 or (expect_substr and expect_substr not in out):
        failures.append(label)
        print(out)
        print(f"   FAILED ({label})")
    else:
        print(f"   PASS ({label})")


def compile_tb(*sources, out, extra=()):
    binf = os.path.join(sim, out)
    c = subprocess.run(["iverilog", "-g2012", *extra, "-o", binf, *sources],
                       cwd=ROOT, capture_output=True, text=True)
    if c.returncode:
        failures.append(out)
        print(c.stderr)
        return None
    return binf


# 1. unit testbenches
for mod, tb in [("addr_decode", "tb_addr_decode"), ("tag_ram", "tb_tag_ram"),
                ("valid_ram", "tb_valid_ram"), ("data_ram", "tb_data_ram")]:
    binf = compile_tb(os.path.join("rtl", f"{mod}.v"), os.path.join("tb", f"{tb}.v"),
                      out=f"ut_{mod}")
    if binf:
        run_sim(binf, f"unit {mod}", expect_substr="PASS")

# 2. directed testbench (B-1 directed list) + waveform dump
binf = compile_tb(*RTL[1], MEM, "tb/tb_cache_basic.v", out="a.out")
if binf:
    run_sim(binf, "directed tb_cache_basic", expect_substr="ALL TESTS PASSED")

# 3. parameterized directed TBs (Gate A)
for tag, opts in [("1k16", []),
                  ("2k32", ["-Ptb_cache_params.CACHE_BYTES=2048",
                            "-Ptb_cache_params.BLOCK_BYTES=32"])]:
    binf = compile_tb(*RTL[1], MEM, "tb/tb_cache_params.v", out=f"ut_params_{tag}",
                      extra=opts)
    if binf:
        run_sim(binf, f"params {tag}", expect_substr="ALL PARAM TESTS PASSED")

# 4. trace-driven TB on all traces, both designs (B-2/E-3, B-4 assertions)
for w in (1, 2):
    binf = compile_tb(*RTL[w], MEM, "tb/tb_cache_trace.v", out=f"tb_trace_w{w}",
                      extra=[f"-Ptb_cache_trace.WAYS={w}"])
    if binf:
        for t in TRACES:
            p = subprocess.run(["vvp", os.path.join("sim", f"tb_trace_w{w}"),
                                f"+trace=traces/{t}.trace"],
                               cwd=ROOT, capture_output=True, text=True)
            out = p.stdout + p.stderr
            if p.returncode != 0 or "TRACE PASS" not in out:
                failures.append(f"trace w{w} {t}")
                print(out)
                print(f"   FAILED (trace w{w} {t})")
            else:
                print(f"   PASS (trace w{w} {t})")

# 4b. conflict-miss regression: 2-way must fix the DM thrash (E-4)
binf = compile_tb(*RTL[1], *RTL[2][4:], MEM, "tb/tb_conflict_2way.v",
                  out="tb_conflict")
if binf:
    run_sim(binf, "conflict 2-way fix (E-4)", expect_substr="CONFLICT TEST PASSED")

# 5. crosscheck vs Python model, both designs (B-3/E-3)
for w in (1, 2):
    p = subprocess.run(["python3", "scripts/crosscheck.py", "--ways", str(w)],
                       cwd=ROOT, capture_output=True, text=True)
    out = p.stdout + p.stderr
    if p.returncode != 0 or "CROSSCHECK OK" not in out:
        failures.append(f"crosscheck w{w}")
        print(out)
        print(f"   FAILED (crosscheck w{w})")
    else:
        print(f"   PASS (crosscheck w{w})")

print()
if failures:
    print(f"REGRESSION FAIL ({len(failures)} failing: {', '.join(failures)})")
    sys.exit(1)
print("REGRESSION PASS")
