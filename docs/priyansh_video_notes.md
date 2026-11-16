# Priyansh video segment (3:30-4:15)

Talking points (about 45 seconds, roughly 110 words):

> To check the cache beyond a few directed tests, I wrote a trace generator
> and a Python reference model. The generator makes five traces of 10,000
> accesses each: sequential, random, a loop over a small working set, a
> 64-byte stride, and a matrix-multiply pattern. The model implements the
> exact same cache: 1 KB, 16-byte blocks, direct-mapped, write-through, no
> write allocate. The results match what locality predicts. Sequential gets
> 75 percent, because one miss brings in four words. The loop gets 99.7
> percent. Random and stride get almost nothing. These are the golden numbers
> that the RTL counters will be checked against in Phase II.

## On screen

Run one command per trace and show the printed hit rate:

```sh
python3 scripts/cache_model.py traces/sequential.trace
python3 scripts/cache_model.py traces/loop.trace
python3 scripts/cache_model.py traces/stride.trace
```

Then show the table from the README (the numbers below come from
`cache_model.py` and match the README):

| Trace      | Hit rate |
|------------|----------|
| sequential | 75.00%   |
| random     | 0.12%    |
| loop       | 99.68%   |
| stride     | 0.00%    |
| matmul     | 88.85%   |

## AMAT idea (one or two sentences, do not quote measured numbers yet)

Average memory access time is `AMAT = hit_time + miss_rate * miss_penalty`.
Hit time is 1 cycle. The miss penalty will be measured from the RTL in
Phase II (a refill is 4 words at `MEM_LATENCY` = 10 cycles each, so about
40 cycles plus FSM overhead). The baseline with no cache costs
`MEM_LATENCY` on every access. So the cache clearly wins on the loop trace,
and the numbers will show where whole-block refills help or hurt.

## If asked

- Why is sequential exactly 75%? Four words share a block, so 1 miss then 3 hits.
- Why is stride 0%? A 64-byte stride skips whole 16-byte blocks, so every
  access is a new block.
- Does the model count write misses as misses? Yes, any access that does not
  hit counts as a miss, the same as the RTL `cnt_miss`.
