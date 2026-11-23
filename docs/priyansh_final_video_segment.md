# Priyansh final video segment: Experiments & Results (2:50-4:20)

All numbers below come from `results/*.csv` regenerated with `make results`
and `python3 scripts/analyze.py` (checked on 2026-11-23: `make regress` prints
REGRESSION PASS and `make crosscheck` exits 0).

## Script (about 90 seconds, about 230 words)

> "Now the results. We generated six traces of 10,000 accesses each:
> sequential, random, a loop over a small working set, a 64-byte stride, a
> matrix-multiply pattern, and a random-with-locality trace for the sweeps.
>
> The RTL counters match my independent Python model exactly on every trace.
> That is the crosscheck, and it exits zero.
>
> Hit rates, straight from `hit_rates.csv`: sequential is 75 percent, one miss
> per four-word block. The loop is 99.7 percent. Matmul is 88.9. Random is
> 0.1 percent and the 64-byte stride is exactly zero, because every access
> lands in a fresh block.
>
> For AMAT, the hit time is one cycle and a read miss costs 55 cycles,
> measured from the RTL refill. Against a no-cache baseline of 10 cycles per
> access, the loop trace is about four times faster, and matmul about 1.7
> times. But sequential and random are slower than no cache at all, because
> we refill a whole block for every miss. That is an honest result.
>
> The size sweep shows hit rate climbing with capacity, from about 1 percent
> at 256 bytes to 17 percent at 4 kilobytes on the locality trace. Block size
> matters much less.
>
> Everything regenerates with `make results`."

## On screen (in order)

1. `results/hit_rates.csv` (or the table below), pointing at each row as you name it.
2. Terminal: `make crosscheck`, ending on the line `CROSSCHECK OK`.
3. Terminal: `python3 scripts/analyze.py`, pointing at the `measured` and `no-cache` columns.
4. `results/hit_rate_vs_cache.png`, then `results/hit_rate_vs_block.png`.

## Numbers to read (from `results/amat_measured.csv`)

| Trace      | Hit rate | AMAT (cycles) | No cache | Speedup |
|------------|----------|---------------|----------|---------|
| sequential | 75.00%   | 14.75         | 10       | 0.68x   |
| random     | 0.12%    | 47.46         | 10       | 0.21x   |
| loop       | 99.68%   | 2.48          | 10       | 4.04x   |
| stride     | 0.00%    | 56.00         | 10       | 0.18x   |
| matmul     | 88.85%   | 5.86          | 10       | 1.71x   |
| locality   | 4.59%    | 45.41         | 10       | 0.22x   |

## Do not say

- "8.5 times faster on the loop" (the `amat.csv` figure). That formula charges
  every miss 55 cycles and every hit 1 cycle, but loop writes cost about 13
  cycles each (write-through). The measured value is 4.04x.
- "Hit rate climbs with block size." In the sweep it does not: at 256 bytes
  bigger blocks lower the hit rate, and at 4 KB the best block is 32 bytes.
- "The 2-way design is better." On these traces it is equal or slightly worse
  (matmul 88.85% vs 86.57%); see `results/design_comparison.csv`.

## If asked

- Why is AMAT above the no-cache cost for sequential? Hit rate is only 75%
  and each miss pays a 55-cycle four-word refill: 1 + 0.25 x 55 = 14.75 > 10.
- Why do formula and measured AMAT differ on loop? Formula: 1 + miss rate x 55.
  Measured: 1 + stall cycles per access, which includes the write-through
  cost of the loop's writes. They agree on read-only traces.
- Why is the crosscheck exact? The Python model and RTL implement the same
  index/tag mapping and the same write-through, no-allocate rule, so hit and
  miss counts must be identical.
