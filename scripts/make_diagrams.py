#!/usr/bin/env python3
"""Generate cache diagrams in docs/ for the report (P1-6)."""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs")
os.makedirs(OUT, exist_ok=True)

C_CPU, C_CTRL, C_RAM, C_MEM, C_DEC = "#dbe9ff", "#fff3cd", "#e2f0d9", "#f8d7da", "#ececec"
EDGE = "#444444"


def box(ax, x, y, w, h, text, fc, fs=10, sub=None):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02",
                                fc=fc, ec=EDGE, lw=1.2))
    cy = y + h / 2 + (0.28 if sub else 0)
    ax.text(x + w / 2, cy, text, ha="center", va="center", fontsize=fs, weight="bold")
    if sub:
        ax.text(x + w / 2, y + h / 2 - 0.42, sub, ha="center", va="center",
                fontsize=7.5, color="#333333")


def arrow(ax, x1, y1, x2, y2, rad=0.0):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle="-|>",
                                 mutation_scale=13, lw=1.2, color=EDGE,
                                 connectionstyle=f"arc3,rad={rad}"))


def alabel(ax, x, y, text, fs=8):
    ax.text(x, y, text, ha="center", va="center", fontsize=fs, color="#333333",
            bbox=dict(fc="white", ec="none", pad=1.0))


# ================= block diagram =================
fig, ax = plt.subplots(figsize=(12.5, 7))
ax.set_xlim(0, 14.6); ax.set_ylim(0, 8); ax.axis("off")
ax.set_title("Direct-Mapped Cache Controller -- Block Diagram (1 KB, 16 B blocks, 64 lines)",
             fontsize=12, weight="bold")

# address split bar (top)
ax.text(7, 7.75, "32-bit address split", ha="center", fontsize=9)
bar = [(0.6, 3.4, "tag [31:10]   (22 bits)", "#ffd6d6"),
       (4.0, 2.4, "index [9:4]   (6 bits)", "#d6ffd6"),
       (6.4, 2.0, "offset [3:0]  (4 bits)", "#d6e4ff")]
for x, w, t, c in bar:
    ax.add_patch(plt.Rectangle((x, 7.05), w, 0.5, fc=c, ec=EDGE))
    ax.text(x + w / 2, 7.3, t, ha="center", va="center", fontsize=8.5)

# cache_top container
ax.add_patch(FancyBboxPatch((3.6, 0.4), 8.9, 6.1, boxstyle="round,pad=0.03",
                            fc="none", ec="#888888", lw=1.4, linestyle="--"))
ax.text(8.05, 6.2, "cache_top", ha="center", fontsize=11, style="italic", weight="bold")

# columns: CPU | controller/decode | RAMs | memory
box(ax, 0.4, 3.4, 2.4, 2.2, "CPU side", C_CPU, fs=11,
    sub="req / we / addr[31:0]\nwdata[31:0]\nrdata / ready")

box(ax, 5.0, 4.3, 2.6, 1.7, "cache_controller", C_CTRL, fs=10,
    sub="FSM: IDLE / COMPARE /\nREFILL / WRITE_THRU / DONE")
box(ax, 5.0, 2.6, 2.6, 0.8, "perf counters", "#f2f2f2", fs=9,
    sub="access / hit / miss / read / write / stall")
box(ax, 5.0, 1.0, 2.6, 0.9, "addr_decode", C_DEC, fs=9,
    sub="tag | index | word_off")

box(ax, 9.0, 5.0, 2.9, 0.85, "tag_ram", C_RAM, fs=9.5, sub="64 lines x 22 b")
box(ax, 9.0, 3.9, 2.9, 0.85, "valid_ram", C_RAM, fs=9.5, sub="64 lines x 1 b (cleared on reset)")
box(ax, 9.0, 2.8, 2.9, 0.85, "data_ram", C_RAM, fs=9.5, sub="64 lines x 4 words x 32 b")

box(ax, 12.7, 0.9, 1.7, 2.2, "Main\nmemory", C_MEM, fs=10,
    sub="word-wide\nMEM_LATENCY\n= 10 / word")

# CPU <-> controller
arrow(ax, 2.8, 5.2, 5.0, 5.2);  alabel(ax, 3.9, 5.45, "req / we / addr / wdata")
arrow(ax, 5.0, 4.5, 2.8, 4.2);  alabel(ax, 3.9, 4.6, "rdata / ready")

# controller -> RAMs (write ports)
arrow(ax, 7.6, 5.6, 9.0, 5.55); alabel(ax, 8.3, 5.85, "tag wr (we/addr/data)")
arrow(ax, 7.6, 5.1, 9.0, 4.4);  alabel(ax, 8.3, 4.85, "valid wr")
arrow(ax, 7.6, 4.55, 9.0, 3.25); alabel(ax, 8.1, 3.6, "data wr")

# RAMs -> controller (read data q)
arrow(ax, 9.0, 5.25, 7.6, 4.85, rad=-0.15); alabel(ax, 8.45, 5.35, "q")
arrow(ax, 9.0, 4.15, 7.6, 4.65, rad=0.15);  alabel(ax, 8.3, 4.25, "q")

# decode -> RAM read addresses
arrow(ax, 7.6, 1.45, 10.4, 2.75, rad=0.3)
alabel(ax, 9.6, 1.6, "sync read addr: {index, word_off} / index")

# controller <-> memory (routed below the RAM column)
arrow(ax, 7.6, 4.35, 12.7, 2.7, rad=-0.35)
alabel(ax, 10.3, 2.35, "mem_req / we / addr / wdata")
arrow(ax, 12.7, 1.7, 7.6, 4.15, rad=0.35)
alabel(ax, 11.2, 1.05, "mem_rdata / mem_ready")

fig.savefig(os.path.join(OUT, "cache_block_diagram.png"), dpi=150, bbox_inches="tight")
plt.close(fig)

# ================= FSM diagram =================
fig, ax = plt.subplots(figsize=(10.5, 6.5))
ax.set_xlim(0, 13); ax.set_ylim(0, 7.6); ax.axis("off")
ax.set_title("cache_controller FSM", fontsize=12, weight="bold")

S = {"IDLE": (1.6, 6.2), "COMPARE": (6.0, 6.2), "REFILL": (10.8, 6.2),
     "WRITE_THRU": (10.8, 2.2), "DONE": (6.0, 2.2)}
for name, (x, y) in S.items():
    ax.add_patch(plt.Circle((x, y), 1.0, fc="#eef4ff", ec=EDGE, lw=1.4))
    ax.text(x, y, name, ha="center", va="center", fontsize=9.5, weight="bold")

def sarrow(a, b, label, lx, ly, rad=0.0):
    (x1, y1), (x2, y2) = S[a], S[b]
    arrow(ax, x1, y1, x2, y2, rad=rad)
    alabel(ax, lx, ly, label, fs=8.5)

sarrow("IDLE", "COMPARE", "cpu_req:\nlatch addr/we/wdata", 3.6, 6.9, rad=-0.25)
sarrow("COMPARE", "DONE", "read hit:\ncpu_rdata <= dt_q", 4.4, 4.2, rad=0.3)
sarrow("COMPARE", "REFILL", "read miss:\nrefill whole block", 8.4, 7.0, rad=-0.25)
sarrow("COMPARE", "WRITE_THRU", "write (hit:\nalso update\nthe cached word)", 9.2, 4.2, rad=0.25)
sarrow("REFILL", "DONE", "4 words done:\nset valid + tag", 8.6, 4.9, rad=-0.15)
sarrow("WRITE_THRU", "DONE", "mem_ready", 8.7, 1.9, rad=0.15)
sarrow("DONE", "IDLE", "cpu_ready\npulses 1 cycle", 3.4, 1.8, rad=-0.35)

ax.text(6.5, 0.35,
        "Rules: valid bits are cleared on reset.  Writes never allocate on miss (write-through).\n"
        "REFILL issues word reads at block_base + 4*i for i = 0..3, waiting for mem_ready on each word.",
        ha="center", fontsize=9, color="#333333")

fig.savefig(os.path.join(OUT, "cache_controller_fsm.png"), dpi=150, bbox_inches="tight")
plt.close(fig)
print("wrote docs/cache_block_diagram.png and docs/cache_controller_fsm.png")
