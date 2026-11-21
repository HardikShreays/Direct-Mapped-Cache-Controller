#!/usr/bin/env python3
"""Generate the 5 memory traces (P1-5 / C-1), 10,000 accesses each.

Format: 'R 0xADDR' or 'W 0xADDR 0xDATA'. All addresses are word-aligned.
Seeded, so output is reproducible. (Phase II adds locality.trace for C-4.)

Usage: python3 scripts/gen_traces.py [--out traces] [--n 10000]
"""
import argparse
import os
import random

WORD = 4
SEED = 6  # Project 6


def fmt(op, addr, rng):
    if op == "W":
        return f"W 0x{addr:08X} 0x{rng.getrandbits(32):08X}"
    return f"R 0x{addr:08X}"


def sequential(n, rng):
    """Word reads walking forward: ~75% hits with 4 words per block."""
    return [("R", i * WORD) for i in range(n)]


def random_trace(n, rng):
    """Uniform random words over 1MB (>> 1KB), 20% writes: near-zero hit rate."""
    out = []
    for _ in range(n):
        addr = rng.randrange(0, 1 << 20, WORD)
        out.append(("W" if rng.random() < 0.2 else "R", addr))
    return out


def loop(n, rng):
    """Repeatedly sweep a 512B working set (<1KB), 10% writes: >95% after warm-up."""
    size = 512
    words = size // WORD
    out = []
    for i in range(n):
        out.append(("W" if i % 10 == 9 else "R", (i % words) * WORD))
    return out


def stride(n, rng):
    """Stride 64B over a large array: every access touches a new block."""
    return [("R", 0x10000 + i * 64) for i in range(n)]


def matmul(n, rng):
    """C=A*B on DIMxDIM int32 matrices (row-major): reads A[i][k], B[k][j], then C[i][j] write."""
    dim = 16
    a, b, c = 0x00000, 0x10000, 0x20000
    out = []
    for i in range(dim):
        for j in range(dim):
            for k in range(dim):
                out.append(("R", a + (i * dim + k) * WORD))
                out.append(("R", b + (k * dim + j) * WORD))
            out.append(("W", c + (i * dim + j) * WORD))
    # 16^3*2 + 16^2 = 8448 accesses per pass; repeat to reach n
    reps = -(-n // len(out))
    return (out * reps)[:n]


def locality(n, rng):
    """Random with locality: 85% in 2KB around 8 hotspots over 1MB, 15% uniform, 20% writes"""
    out = []
    hotspots = [rng.randrange(0, 1 << 20, WORD) for _ in range(8)]
    for _ in range(n):
        if rng.random() < 0.85:
            base = rng.choice(hotspots)
            addr = (base + rng.randrange(0, 2048, WORD)) % (1 << 20)
        else:
            addr = rng.randrange(0, 1 << 20, WORD)
        out.append(("W" if rng.random() < 0.2 else "R", addr))
    return out


TRACES = {
    "sequential": sequential,
    "random": random_trace,
    "loop": loop,
    "stride": stride,
    "matmul": matmul,
    "locality": locality,
}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default="traces")
    ap.add_argument("--n", type=int, default=10000)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for name, fn in TRACES.items():
        rng = random.Random(f"{SEED}-{name}")
        accesses = fn(args.n, rng)
        path = os.path.join(args.out, f"{name}.trace")
        with open(path, "w") as f:
            f.write(f"# {name}: {fn.__doc__.strip()}\n")
            f.writelines(fmt(op, addr, rng) + "\n" for op, addr in accesses)
        print(f"wrote {path} ({len(accesses)} accesses)")


if __name__ == "__main__":
    main()
