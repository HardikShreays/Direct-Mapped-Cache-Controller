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


def simulate(accesses, cache_bytes=1024, block_bytes=16, ways=1):
    """Run (op, addr) accesses through the cache; return a Result.

    ways=1 is the direct-mapped design; ways=2 is the 2-way set-associative
    extension with true LRU replacement (matches rtl/cache_top_2way.v).
    """
    if cache_bytes % block_bytes or block_bytes & (block_bytes - 1):
        raise ValueError("block size must be a power of two dividing cache size")
    lines = cache_bytes // block_bytes
    if lines & (lines - 1):
        raise ValueError("number of lines must be a power of two")
    if ways not in (1, 2) or lines % ways:
        raise ValueError("ways must be 1 or 2 and must divide the line count")
    offset_bits = block_bytes.bit_length() - 1
    sets = lines // ways
    set_bits = sets.bit_length() - 1 if sets > 1 else 0

    # per set: list of ways, index 0 = most recently used ... last = LRU
    lru = [[None] * ways for _ in range(sets)]  # ordered tag lists, None = invalid
    n = hits = reads = writes = read_hits = write_hits = 0

    def touch(s, w):
        l = lru[s]
        l.insert(0, l.pop(w))   # move to MRU position

    for op, addr in accesses:
        s = (addr >> offset_bits) & (sets - 1) if sets > 1 else 0
        tag = addr >> (offset_bits + set_bits)
        order = lru[s]
        way = order.index(tag) if tag in order else None
        hit = way is not None
        n += 1
        if op == "R":
            reads += 1
            if hit:
                read_hits += 1
                touch(s, way)
            else:
                # replace the LRU way (last in the list); refill makes it MRU
                lru[s] = [tag] + order[:-1]
        else:
            writes += 1
            if hit:
                write_hits += 1  # write-through updates cache word + memory
                touch(s, way)
            # write miss: memory only, no allocate (both designs)
        hits += hit

    return Result(n, hits, n - hits, reads, writes, read_hits, write_hits)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("trace")
    ap.add_argument("--cache-bytes", type=int, default=1024)
    ap.add_argument("--block-bytes", type=int, default=16)
    ap.add_argument("--ways", type=int, default=1, choices=(1, 2))
    args = ap.parse_args(argv)
    try:
        r = simulate(parse_trace(args.trace), args.cache_bytes, args.block_bytes,
                     args.ways)
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
