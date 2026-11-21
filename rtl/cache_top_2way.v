// cache_top_2way.v -- 2-way set-associative cache: controller + per-way RAMs
// + LRU + perf counters (E-1, E-2)
//
// Identical CPU/memory/counter interface to cache_top.v, so testbenches can
// swap between the two designs. Both ways are read in parallel every cycle;
// hit/miss resolution adds no latency over the direct-mapped design.
module cache_top_2way #(
    parameter ADDR_W      = 32,
    parameter CACHE_BYTES = 1024,
    parameter BLOCK_BYTES = 16,
    parameter OFF_BITS    = $clog2(BLOCK_BYTES),
    parameter N_SETS      = CACHE_BYTES / (2 * BLOCK_BYTES),
    parameter SET_BITS    = $clog2(N_SETS),
    parameter TAG_BITS    = ADDR_W - OFF_BITS - SET_BITS,
    parameter WORDS       = BLOCK_BYTES / 4,
    parameter WORD_OFF_W  = OFF_BITS - 2,
    parameter DT_AW       = SET_BITS + WORD_OFF_W
)(
    input  wire              clk,
    input  wire              rst,

    // CPU side
    input  wire              cpu_req,
    input  wire              cpu_we,
    input  wire [ADDR_W-1:0] cpu_addr,
    input  wire [31:0]       cpu_wdata,
    output wire [31:0]       cpu_rdata,
    output wire              cpu_ready,

    // Memory side
    output wire              mem_req,
    output wire              mem_we,
    output wire [ADDR_W-1:0] mem_addr,
    output wire [31:0]       mem_wdata,
    input  wire [31:0]       mem_rdata,
    input  wire              mem_ready,

    // Performance counters
    output wire [31:0]       cnt_access,
    output wire [31:0]       cnt_hit,
    output wire [31:0]       cnt_miss,
    output wire [31:0]       cnt_read,
    output wire [31:0]       cnt_write,
    output wire [31:0]       cnt_stall_cycles
);
    // ---- address decode of the live CPU address ----
    // (set index selects the RAM row; both ways are read every cycle)
    wire [SET_BITS-1:0] dec_set;

    addr_decode #(
        .ADDR_W      (ADDR_W),
        .CACHE_BYTES (CACHE_BYTES / 2),   // one way's worth of lines
        .BLOCK_BYTES (BLOCK_BYTES)
    ) u_decode (
        .addr     (cpu_addr),
        .offset   (),
        .word_off (),
        .index    (dec_set),
        .tag      ()
    );

    wire [DT_AW-1:0] r_daddr = {dec_set, cpu_addr[OFF_BITS-1:2]};

    // ---- RAM write-port wiring ----
    wire                dt_we0, dt_we1;
    wire [DT_AW-1:0]    dt_waddr;
    wire [31:0]         dt_wdata;
    wire [31:0]         dt_q0, dt_q1;

    wire                tag_we0, tag_we1;
    wire [SET_BITS-1:0] tag_waddr;
    wire [TAG_BITS-1:0] tag_wdata;
    wire [TAG_BITS-1:0] tag_q0, tag_q1;

    wire                vld_we0, vld_we1;
    wire [SET_BITS-1:0] vld_waddr;
    wire                vld_wdata;
    wire                vld_q0, vld_q1;

    wire                lru_we;
    wire [SET_BITS-1:0] lru_waddr;
    wire                lru_wdata;
    wire                lru_q;

    cache_controller_2way #(
        .ADDR_W      (ADDR_W),
        .CACHE_BYTES (CACHE_BYTES),
        .BLOCK_BYTES (BLOCK_BYTES)
    ) u_ctrl (
        .clk              (clk),
        .rst              (rst),
        .cpu_req          (cpu_req),
        .cpu_we           (cpu_we),
        .cpu_addr         (cpu_addr),
        .cpu_wdata        (cpu_wdata),
        .cpu_rdata        (cpu_rdata),
        .cpu_ready        (cpu_ready),
        .dt_we0           (dt_we0),
        .dt_we1           (dt_we1),
        .dt_waddr         (dt_waddr),
        .dt_wdata         (dt_wdata),
        .dt_q0            (dt_q0),
        .dt_q1            (dt_q1),
        .tag_we0          (tag_we0),
        .tag_we1          (tag_we1),
        .tag_waddr        (tag_waddr),
        .tag_wdata        (tag_wdata),
        .tag_q0           (tag_q0),
        .tag_q1           (tag_q1),
        .vld_we0          (vld_we0),
        .vld_we1          (vld_we1),
        .vld_waddr        (vld_waddr),
        .vld_wdata        (vld_wdata),
        .vld_q0           (vld_q0),
        .vld_q1           (vld_q1),
        .lru_we           (lru_we),
        .lru_waddr        (lru_waddr),
        .lru_wdata        (lru_wdata),
        .lru_q            (lru_q),
        .mem_req          (mem_req),
        .mem_we           (mem_we),
        .mem_addr         (mem_addr),
        .mem_wdata        (mem_wdata),
        .mem_rdata        (mem_rdata),
        .mem_ready        (mem_ready),
        .cnt_access       (cnt_access),
        .cnt_hit          (cnt_hit),
        .cnt_miss         (cnt_miss),
        .cnt_read         (cnt_read),
        .cnt_write        (cnt_write),
        .cnt_stall_cycles (cnt_stall_cycles)
    );

    // ---- way 0 ----
    tag_ram #(.N_LINES (N_SETS), .DWIDTH (TAG_BITS)) u_tag0 (
        .clk(clk), .we(tag_we0), .waddr(tag_waddr), .wdata(tag_wdata),
        .raddr(dec_set), .q(tag_q0));

    valid_ram #(.N_LINES (N_SETS)) u_vld0 (
        .clk(clk), .rst(rst), .we(vld_we0), .waddr(vld_waddr),
        .wdata(vld_wdata), .raddr(dec_set), .q(vld_q0));

    data_ram #(.N_LINES (N_SETS), .WORDS (WORDS)) u_dt0 (
        .clk(clk), .we(dt_we0), .waddr(dt_waddr), .wdata(dt_wdata),
        .raddr(r_daddr), .q(dt_q0));

    // ---- way 1 ----
    tag_ram #(.N_LINES (N_SETS), .DWIDTH (TAG_BITS)) u_tag1 (
        .clk(clk), .we(tag_we1), .waddr(tag_waddr), .wdata(tag_wdata),
        .raddr(dec_set), .q(tag_q1));

    valid_ram #(.N_LINES (N_SETS)) u_vld1 (
        .clk(clk), .rst(rst), .we(vld_we1), .waddr(vld_waddr),
        .wdata(vld_wdata), .raddr(dec_set), .q(vld_q1));

    data_ram #(.N_LINES (N_SETS), .WORDS (WORDS)) u_dt1 (
        .clk(clk), .we(dt_we1), .waddr(dt_waddr), .wdata(dt_wdata),
        .raddr(r_daddr), .q(dt_q1));

    // ---- LRU ----
    lru_ram #(.N_SETS (N_SETS)) u_lru (
        .clk(clk), .rst(rst), .we(lru_we), .waddr(lru_waddr),
        .wdata(lru_wdata), .raddr(dec_set), .q(lru_q));
endmodule
