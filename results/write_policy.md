# Write-through vs write-back: analytic comparison (C-5)

Measured on the RTL at the default geometry (1KB cache, 16B blocks,
MEM_LATENCY=10 cycles/word):

- Read miss (refill, 4 word handshakes): **55 cycles**
- Write hit (cache word update + write-through): **13 cycles**
- Write miss (memory only, no allocate): **13 cycles**

## Analytic cycle cost per write-dominant workload

| Metric                              | Write-through (this design)      | Write-back (analytic)                       |
|-------------------------------------|----------------------------------|---------------------------------------------|
| Write hit cost                      | 13 cycles (memory write) | 1 cycle (dirty bit set)                     |
| Dirty line eviction                 | none (line always clean)         | refill + 10+ cycles to write back |
| Extra state                         | none                             | 1 dirty bit per line (64 bits total)        |
| Memory write traffic on 100% dirty evictions | 1 word per write (immediate) | 1 block (16B) per evicted line            |
| Read-after-write visibility         | memory always current (safe)     | stale until writeback                       |

For the locality trace (2051 writes of 10000 accesses), write-through adds
roughly 26663 write stall cycles. A write-back design would reduce
this to ~2051 one-cycle dirty-bit updates, but every dirty eviction would
then pay a 10+ cycle writeback on top of the refill, and the controller
would need dirty bits, an eviction writeback path, and a write buffer to
avoid stalling on eviction. Given the small 1KB cache and high eviction
rate (a new block refills the same line frequently in this workload), the
writeback traffic would approach one block per miss, so write-through is
the simpler and, at this scale, competitive policy.
