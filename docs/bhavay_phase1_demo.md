# Bhavay Goyal - Phase 1 demo notes (2:00-3:30)

## Commands and waveform

1. Run `make sim`. Point out the four `PASS` lines and the final
   `ALL TESTS PASSED` line.
2. Open the waveform with `gtkwave sim/cache.vcd`.
3. Add these signals: `clk`, `rst`, `cpu_req`, `cpu_addr`, `cpu_rdata`,
   `cpu_ready`, `mem_req`, `mem_addr`, `mem_rdata`, `mem_ready`, and
   `dut.u_ctrl.state`.
4. At the first CPU read of `0x00000000`, show that `cpu_ready` stays low
   while four memory completions occur at `0x00`, `0x04`, `0x08`, and
   `0x0C`. The memory model takes 10 clock cycles for each accepted word.
5. At the next read of `0x00000000`, show `cpu_ready` without any new
   `mem_ready` pulse. That is the cache hit. The reads at offsets `0x04`,
   `0x08`, and `0x0C` are hits too.
6. Later, show `0x00000400` refilling the same index with a different tag.
   The following `0x00000000` access refills again because its line was
   replaced.

The report calls the controller a five-state FSM, but the actual RTL also has
`S_REFILL_GAP`. This state drops `mem_req` for one cycle between words so the
memory model can recognize each refill request as a separate transaction. The
cache geometry and requested 10-cycle memory latency still match the frozen
specification.

## Approximate 90-second Hinglish narration

"Hi, main Bhavay Goyal hoon. Phase 1 mein mera contribution behavioral main
memory model aur basic cache testbench hai. Sabse pehle main `make sim` run
kar raha hoon. Yahan four directed checks pass ho rahe hain, aur end mein exact
message `ALL TESTS PASSED` aa raha hai.

Memory model word-wide hai aur default latency ten clock cycles hai. Request
accept hote hi address, write-enable aur write-data latch ho jaate hain, isliye
pending transaction ke beech duplicate request accept nahi hoti. Initial data
formula `A5000000 plus byte address` hai.

Ab waveform mein CPU aur memory handshake signals dekhiye. First read address
zero ek cold miss hai. `cpu_ready` low rehta hai, aur memory addresses zero,
four, eight aur C par four completed reads dikhte hain. Isse poora sixteen-byte
block refill hota hai. Same address dobara read karne par koi new memory
transaction nahi hoti, so this is a hit. Same block ke offsets four, eight aur
C bhi hits hain.

Finally address four-hundred-hex ka index same hai but tag different hai, so
new four-word refill hota hai. Phir address zero read karne par dobara miss
hota hai, which proves conflict replacement. Testbench mein per-transaction
timeout aur global watchdog bhi hai, so broken RTL simulation hang nahi karega.
Yeh mera Phase 1 verification contribution tha."

## Short explanation for questions

- Address bits `[3:0]` select the byte in a 16-byte block; `[3:2]` select its
  word, `[9:4]` select one of 64 lines, and `[31:10]` are the tag.
- The memory model converts byte addresses to word indexes with `address >> 2`
  and reports unsupported unaligned or out-of-range accesses as failures.
- Hits and misses are proved from observed memory completions, not only from
  performance counters.
