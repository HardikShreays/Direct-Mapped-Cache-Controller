// cache_controller.v -- direct-mapped cache FSM (P1-3)
//
// Spec (frozen): 32-bit address, 1KB cache, 16B blocks (4 words), 64 lines,
// direct-mapped, write-through + no-write-allocate.
//
// FSM:
//   IDLE       wait for cpu_req; latch addr/we/wdata
//   COMPARE    hit = valid && tag match
//                read hit          -> DONE (return data)
//                read miss         -> REFILL
//                write hit         -> update cache word, -> WRITE_THRU
//                write miss        -> WRITE_THRU (memory only, no allocate)
//   REFILL     4 word reads from memory into data RAM, then set valid+tag
//   WRITE_THRU one memory write, wait mem_ready
//   DONE       cpu_ready pulses one cycle, return to IDLE
//
// Read ports of the RAMs are wired to the *live* cpu_addr in cache_top, so
// the tag/valid/data read out one cycle after a request is accepted and are
// compared at the end of the COMPARE cycle (1-cycle hit latency).
module cache_controller #(
    parameter ADDR_W      = 32,
    parameter CACHE_BYTES = 1024,
    parameter BLOCK_BYTES = 16,
    parameter OFF_BITS    = $clog2(BLOCK_BYTES),
    parameter N_LINES     = CACHE_BYTES / BLOCK_BYTES,
    parameter IDX_BITS    = $clog2(N_LINES),
    parameter TAG_BITS    = ADDR_W - OFF_BITS - IDX_BITS,
    parameter WORDS       = BLOCK_BYTES / 4,
    parameter WORD_OFF_W  = OFF_BITS - 2,
    parameter DT_AW       = IDX_BITS + WORD_OFF_W,
    parameter REFILL_W    = $clog2(WORDS)
)(
    input  wire               clk,
    input  wire               rst,

    // CPU side
    input  wire               cpu_req,
    input  wire               cpu_we,
    input  wire [ADDR_W-1:0]  cpu_addr,
    input  wire [31:0]        cpu_wdata,
    output reg  [31:0]        cpu_rdata,
    output wire               cpu_ready,

    // data RAM: write port + synchronous read data
    output reg                dt_we,
    output reg  [DT_AW-1:0]   dt_waddr,
    output reg  [31:0]        dt_wdata,
    input  wire [31:0]        dt_q,

    // tag RAM: write port + synchronous read data
    output reg                tag_we,
    output reg  [IDX_BITS-1:0] tag_waddr,
    output reg  [TAG_BITS-1:0] tag_wdata,
    input  wire [TAG_BITS-1:0] tag_q,

    // valid RAM: write port + synchronous read data
    output reg                 vld_we,
    output reg  [IDX_BITS-1:0] vld_waddr,
    output reg                 vld_wdata,
    input  wire                vld_q,

    // memory side (word-wide, per-word handshake)
    output reg                 mem_req,
    output reg                 mem_we,
    output reg  [ADDR_W-1:0]   mem_addr,
    output reg  [31:0]         mem_wdata,
    input  wire [31:0]         mem_rdata,
    input  wire                mem_ready,

    // performance counters
    output reg  [31:0]         cnt_access,
    output reg  [31:0]         cnt_hit,
    output reg  [31:0]         cnt_miss,
    output reg  [31:0]         cnt_read,
    output reg  [31:0]         cnt_write,
    output reg  [31:0]         cnt_stall_cycles
);
    // ---- request decode (of the latched address) ----
    reg [ADDR_W-1:0] req_addr;
    reg              req_we;
    reg [31:0]       req_wdata;
    reg [REFILL_W-1:0] refill_cnt;

    wire [TAG_BITS-1:0]     req_tag   = req_addr[ADDR_W-1:OFF_BITS+IDX_BITS];
    wire [IDX_BITS-1:0]     req_index = req_addr[OFF_BITS+IDX_BITS-1:OFF_BITS];
    wire [WORD_OFF_W-1:0]   req_word  = req_addr[OFF_BITS-1:2];
    wire [ADDR_W-1:0]       block_base = req_addr & ~(BLOCK_BYTES-1);

    // ---- FSM state ----
    localparam S_IDLE       = 3'd0,
               S_COMPARE    = 3'd1,
               S_REFILL     = 3'd2,
               S_REFILL_GAP = 3'd3,   // one idle cycle between refill words
               S_WRITE_THRU = 3'd4,
               S_DONE       = 3'd5;
    reg [2:0] state;

    assign cpu_ready = (state == S_DONE);

    always @(posedge clk) begin
        if (rst) begin
            state            <= S_IDLE;
            mem_req          <= 1'b0;
            mem_we           <= 1'b0;
            mem_addr         <= {ADDR_W{1'b0}};
            mem_wdata        <= 32'h0;
            dt_we            <= 1'b0;
            tag_we           <= 1'b0;
            vld_we           <= 1'b0;
            cpu_rdata        <= 32'h0;
            refill_cnt       <= {REFILL_W{1'b0}};
            cnt_access       <= 32'd0;
            cnt_hit          <= 32'd0;
            cnt_miss         <= 32'd0;
            cnt_read         <= 32'd0;
            cnt_write        <= 32'd0;
            cnt_stall_cycles <= 32'd0;
        end else begin
            // default: single-cycle pulses
            mem_req <= 1'b0;
            mem_we  <= 1'b0;
            dt_we   <= 1'b0;
            tag_we  <= 1'b0;
            vld_we  <= 1'b0;

            case (state)
            S_IDLE: begin
                if (cpu_req) begin
                    req_addr   <= cpu_addr;
                    req_we     <= cpu_we;
                    req_wdata  <= cpu_wdata;
                    cnt_access <= cnt_access + 32'd1;
                    if (cpu_we) cnt_write <= cnt_write + 32'd1;
                    else        cnt_read  <= cnt_read  + 32'd1;
                    state <= S_COMPARE;
                end
            end

            S_COMPARE: begin
                if (vld_q && (tag_q == req_tag)) begin
                    // HIT
                    cnt_hit <= cnt_hit + 32'd1;
                    if (!req_we) begin
                        cpu_rdata <= dt_q;            // data read out at accept edge
                        state     <= S_DONE;
                    end else begin
                        // write hit: update the cached word, then write through
                        dt_we    <= 1'b1;
                        dt_waddr <= {req_index, req_word};
                        dt_wdata <= req_wdata;
                        state    <= S_WRITE_THRU;
                    end
                end else begin
                    // MISS
                    cnt_miss <= cnt_miss + 32'd1;
                    if (!req_we) begin
                        refill_cnt <= {REFILL_W{1'b0}};
                        state      <= S_REFILL;
                    end else begin
                        state <= S_WRITE_THRU;        // write miss: no allocate
                    end
                end
            end

            S_REFILL: begin
                cnt_stall_cycles <= cnt_stall_cycles + 32'd1;
                mem_we <= 1'b0;
                if (!mem_ready) begin
                    // keep requesting the current refill word
                    mem_req  <= 1'b1;
                    mem_addr <= block_base + {refill_cnt, 2'b00};
                end else begin
                    // handshake: write the word into the data RAM
                    dt_we    <= 1'b1;
                    dt_waddr <= {req_index, refill_cnt};
                    dt_wdata <= mem_rdata;
                    if (refill_cnt == req_word)   // remember the requested word
                        cpu_rdata <= mem_rdata;
                    if (refill_cnt == WORDS-1) begin
                        // block complete: install tag + valid
                        tag_waddr <= req_index;
                        tag_wdata <= req_tag;
                        tag_we    <= 1'b1;
                        vld_waddr <= req_index;
                        vld_wdata <= 1'b1;
                        vld_we    <= 1'b1;
                        state     <= S_DONE;
                    end else begin
                        refill_cnt <= refill_cnt + 1'b1;
                        state      <= S_REFILL_GAP;   // drop req one cycle
                    end
                end
            end

            S_REFILL_GAP: begin
                cnt_stall_cycles <= cnt_stall_cycles + 32'd1;
                mem_addr <= block_base + {refill_cnt, 2'b00}; // next word
                state    <= S_REFILL;
            end

            S_WRITE_THRU: begin
                cnt_stall_cycles <= cnt_stall_cycles + 32'd1;
                mem_we    <= 1'b1;
                mem_addr  <= req_addr;
                mem_wdata <= req_wdata;
                if (!mem_ready)
                    mem_req <= 1'b1;      // drop req on the completion edge
                if (mem_ready)
                    state <= S_DONE;
            end

            S_DONE: begin
                state <= S_IDLE;   // cpu_ready pulses this one cycle
            end

            default: state <= S_IDLE;
            endcase
        end
    end
endmodule
