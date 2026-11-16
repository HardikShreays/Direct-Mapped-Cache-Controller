#!/usr/bin/env python3
"""Python reference model of the direct-mapped cache (P1-5).

Spec (frozen): 32-bit address, 1KB cache, 16B blocks, 64 lines,
offset [3:0], index [9:4], tag [31:10], direct-mapped,
write-through + no-write-allocate.

Trace format (one access per line, '#' starts a comment):
    R 0xADDR
    W 0xADDR [0xDATA]

Usage:
    python3 scripts/cache_model.py traces/sequential.trace
    python3 scripts/cache_model.py traces/random.trace --cache-bytes 2048 --block-bytes 32
"""
import argparse
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class Result:
    accesses: int
    hits: int
    misses: int
    reads: int
    writes: int
    read_hits: int
    write_hits: int

    @property
    def hit_rate(self) -> float:
        return self.hits / self.accesses if self.accesses else 0.0


def parse_trace(path):
    """Yield (op, addr) tuples; raises ValueError with line number on bad input."""
    with open(path) as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            if parts[0] not in ("R", "W") or len(parts) < 2:
                raise ValueError(f"{path}:{lineno}: bad trace line: {raw.rstrip()!r}")
            try:
                addr = int(parts[1], 16)
            except ValueError:
                raise ValueError(f"{path}:{lineno}: bad address: {parts[1]!r}") from None
            if not 0 <= addr < 1 << 32:
                raise ValueError(f"{path}:{lineno}: address out of 32-bit range")
            yield parts[0], addr


def simulate(accesses, cache_bytes=1024, block_bytes=16):
    """Run (op, addr) accesses through the cache; return a Result."""
    if cache_bytes % block_bytes or block_bytes & (block_bytes - 1):
        raise ValueError("block size must be a power of two dividing cache size")
    lines = cache_bytes // block_bytes
    if lines & (lines - 1):
        raise ValueError("number of lines must be a power of two")
    offset_bits = block_bytes.bit_length() - 1
    index_bits = lines.bit_length() - 1

    tags = [None] * lines  # None = invalid (valid bits cleared on reset)
    n = hits = reads = writes = read_hits = write_hits = 0

    for op, addr in accesses:
        index = (addr >> offset_bits) & (lines - 1)
        tag = addr >> (offset_bits + index_bits)
        hit = tags[index] == tag
        n += 1
        if op == "R":
            reads += 1
            if hit:
                read_hits += 1
            else:
                tags[index] = tag  # refill whole block
        else:
            writes += 1
            if hit:
                write_hits += 1  # write-through updates cache word + memory
            # write miss: memory only, no allocate
        hits += hit

    return Result(n, hits, n - hits, reads, writes, read_hits, write_hits)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("trace")
    ap.add_argument("--cache-bytes", type=int, default=1024)
    ap.add_argument("--block-bytes", type=int, default=16)
    args = ap.parse_args(argv)
    try:
        r = simulate(parse_trace(args.trace), args.cache_bytes, args.block_bytes)
    except (OSError, ValueError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    print(f"accesses={r.accesses} hits={r.hits} misses={r.misses} "
          f"reads={r.reads} writes={r.writes} "
          f"read_hits={r.read_hits} write_hits={r.write_hits} "
          f"hit_rate={r.hit_rate:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
