# Synthesis resource table (Gate D)

Tool: **Yosys 0.71** (open source). No Vivado machine was available for this
phase, so FPGA vendor numbers (LUT/FF/BRAM counts, Fmax) are **not** reported;
this is stated honestly per plan D-2. Log: `results/synth_yosys.log`.

## 1. Generic gate-level synthesis (`synth -top cache_top; stat`)

The generic flow has no FPGA memory primitives, so the RAM arrays dissolve
into flip-flops + muxes. Design hierarchy totals (1KB cache / 16B blocks):

| Resource                    | Count   | Notes                                        |
|-----------------------------|---------|----------------------------------------------|
| Total cells                 | 26 279  | includes all submodules                      |
| Flip-flops (`$_DFFE_PP_` + `$_DFF_P_` + SDFF) | 10 096 | of which data RAM = 8 192, tag RAM = 1 408 |
| Multiplexers (`$_MUX_`)     | 7 003   |                                              |
| Comb. gates (AND/NAND/OR/NOR/XOR/...) | 9 144 |                                    |

Per module:

| Module            | Cells | FFs  | Muxes | Gates |
|-------------------|-------|------|-------|-------|
| cache_controller  | 1 001 | 139  | 68    | 675   |
| addr_decode       | 0     | 0    | 0     | 0 (pure wiring) |
| data_ram (256x32) | 21 250| 8 224| 5 892 | 7 023 |
| tag_ram (64x22)   | 3 687 | 1 430| 1 002 | 1 214 |
| valid_ram (64x1)  | 341   | 0    | 41    | 245   |

## 2. Memory-inference pass (D-3, before/after check)

With `hierarchy; proc; opt; memory_dff; stat` (the stage an FPGA backend uses
before mapping to block RAM):

| Array     | Memories | Memory bits |
|-----------|----------|-------------|
| data RAM  | 1        | 8 192       |
| tag RAM   | 1        | 1 408       |
| valid RAM | 1        | 64          |
| **Total** | **3**    | **9 664**   |

**D-3 outcome:** no rewrap was needed. The RAMs were already written with
synchronous read ports (`q <= mem[raddr]` on the clock edge), which is the
BRAM-friendly template; Yosys detects all three arrays as true memories
(9 664 bits) that a vendor backend would map to block RAM. The huge FF count
in the generic log is an artifact of the targetless generic flow, not of the
RTL style. Resource numbers were recorded before (gate-level dissolution)
and after (memory detection) to document this.

## 3. Vivado

Not run (no Vivado machine available). If a team member gets access to one,
`synth_design -top cache_top` on an Artix-7 part is expected to report
roughly: ~200 LUTs for controller+decode, 1-2 RAMB18 for the data array,
1 RAMB18 for tags, valid bits in LUTRAM/FFs. These are expectations, not
measurements, and must not be quoted as results.
