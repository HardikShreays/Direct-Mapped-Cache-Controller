// cache_top.v -- cache controller + RAMs + perf counters (P1-3)
//
// CPU side : clk, rst, cpu_req, cpu_we, cpu_addr[31:0], cpu_wdata[31:0],
//            cpu_rdata[31:0], cpu_ready
// Memory   : mem_req, mem_we, mem_addr[31:0], mem_wdata[31:0],
//            mem_rdata[31:0], mem_ready
// Counters : cnt_access, cnt_hit, cnt_miss, cnt_read, cnt_write,
//            cnt_stall_cycles (32-bit each)
module cache_top #(
    parameter ADDR_W      = 32,
    parameter CACHE_BYTES = 1024,
    parameter BLOCK_BYTES = 16,
    parameter OFF_BITS    = $clog2(BLOCK_BYTES),
    parameter N_LINES     = CACHE_BYTES / BLOCK_BYTES,
    parameter IDX_BITS    = $clog2(N_LINES),
    parameter TAG_BITS    = ADDR_W - OFF_BITS - IDX_BITS,
    parameter WORDS       = BLOCK_BYTES / 4,
    parameter WORD_OFF_W  = OFF_BITS - 2,
    parameter DT_AW       = IDX_BITS + WORD_OFF_W
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
    // The synchronous read ports of the RAMs sample this every cycle, so a
    // request accepted on edge T has its tag/valid/data available in the
    // COMPARE cycle (hit latency = 1 cycle).
    wire [OFF_BITS-1:0]   dec_offset;
    wire [WORD_OFF_W-1:0] dec_word;
    wire [IDX_BITS-1:0]   dec_index;
    wire [TAG_BITS-1:0]   dec_tag;

    addr_decode #(
        .ADDR_W      (ADDR_W),
        .CACHE_BYTES (CACHE_BYTES),
        .BLOCK_BYTES (BLOCK_BYTES)
    ) u_decode (
        .addr     (cpu_addr),
        .offset   (dec_offset),
        .word_off (dec_word),
        .index    (dec_index),
        .tag      (dec_tag)
    );

    wire [DT_AW-1:0] r_daddr = {dec_index, dec_word};

    // ---- RAM write-port wiring ----
    wire                dt_we;
    wire [DT_AW-1:0]    dt_waddr;
    wire [31:0]         dt_wdata;
    wire [31:0]         dt_q;

    wire                tag_we;
    wire [IDX_BITS-1:0] tag_waddr;
    wire [TAG_BITS-1:0] tag_wdata;
    wire [TAG_BITS-1:0] tag_q;

    wire                vld_we;
    wire [IDX_BITS-1:0] vld_waddr;
    wire                vld_wdata;
    wire                vld_q;

    cache_controller #(
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
        .dt_we            (dt_we),
        .dt_waddr         (dt_waddr),
        .dt_wdata         (dt_wdata),
        .dt_q             (dt_q),
        .tag_we           (tag_we),
        .tag_waddr        (tag_waddr),
        .tag_wdata        (tag_wdata),
        .tag_q            (tag_q),
        .vld_we           (vld_we),
        .vld_waddr        (vld_waddr),
        .vld_wdata        (vld_wdata),
        .vld_q            (vld_q),
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

    tag_ram #(
        .N_LINES (N_LINES),
        .DWIDTH  (TAG_BITS)
    ) u_tag (
        .clk   (clk),
        .we    (tag_we),
        .waddr (tag_waddr),
        .wdata (tag_wdata),
        .raddr (dec_index),
        .q     (tag_q)
    );

    valid_ram #(
        .N_LINES (N_LINES)
    ) u_vld (
        .clk   (clk),
        .rst   (rst),
        .we    (vld_we),
        .waddr (vld_waddr),
        .wdata (vld_wdata),
        .raddr (dec_index),
        .q     (vld_q)
    );

    data_ram #(
        .N_LINES (N_LINES),
        .WORDS   (WORDS)
    ) u_dt (
        .clk   (clk),
        .we    (dt_we),
        .waddr (dt_waddr),
        .wdata (dt_wdata),
        .raddr (r_daddr),
        .q     (dt_q)
    );
endmodule
