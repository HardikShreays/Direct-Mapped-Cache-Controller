// cache_controller_2way.v -- 2-way set-associative cache FSM with LRU (E-1, E-2)
//
// Same external behaviour and FSM shape as cache_controller.v (direct-mapped),
// extended to two ways:
//   - tag/valid/data RAMs are duplicated per way; both ways are read in
//     parallel every cycle (read ports wired to the live cpu_addr in
//     cache_top_2way, so hit/miss resolves with 1-cycle hit latency)
//   - COMPARE: hit = valid[way] && tag match, for way 0 or way 1
//       read hit  -> return data of the hitting way, DONE
//       read miss -> REFILL into the LRU way
//       write hit -> update the cached word of the hitting way, WRITE_THRU
//       write miss-> WRITE_THRU (memory only, no allocate)
//   - LRU (E-2): one bit per set, updated on every hit and every refill;
//       on miss the LRU way is replaced.
//
// Internal assertion-relevant signal names (state, req_we, refill_cnt)
// deliberately match cache_controller.v so the shared TB monitors apply.
module cache_controller_2way #(
    parameter ADDR_W      = 32,
    parameter CACHE_BYTES = 1024,
    parameter BLOCK_BYTES = 16,
    parameter OFF_BITS    = $clog2(BLOCK_BYTES),
    parameter N_SETS      = CACHE_BYTES / (2 * BLOCK_BYTES),
    parameter SET_BITS    = $clog2(N_SETS),
    parameter TAG_BITS    = ADDR_W - OFF_BITS - SET_BITS,
    parameter WORDS       = BLOCK_BYTES / 4,
    parameter WORD_OFF_W  = OFF_BITS - 2,
    parameter DT_AW       = SET_BITS + WORD_OFF_W,
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

    // per-way data RAM: write ports + synchronous read data
    output reg                dt_we0,
    output reg                dt_we1,
    output reg  [DT_AW-1:0]   dt_waddr,
    output reg  [31:0]        dt_wdata,
    input  wire [31:0]        dt_q0,
    input  wire [31:0]        dt_q1,

    // per-way tag RAM: write ports + synchronous read data
    output reg                tag_we0,
    output reg                tag_we1,
    output reg  [SET_BITS-1:0] tag_waddr,
    output reg  [TAG_BITS-1:0] tag_wdata,
    input  wire [TAG_BITS-1:0] tag_q0,
    input  wire [TAG_BITS-1:0] tag_q1,

    // per-way valid RAM: write ports + synchronous read data
    output reg                 vld_we0,
    output reg                 vld_we1,
    output reg  [SET_BITS-1:0] vld_waddr,
    output reg                 vld_wdata,
    input  wire                vld_q0,
    input  wire                vld_q1,

    // LRU RAM: write port + synchronous read data
    output reg                 lru_we,
    output reg  [SET_BITS-1:0] lru_waddr,
    output reg                 lru_wdata,
    input  wire                lru_q,

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
    reg              refill_way;      // way being refilled (0/1)
    reg              hit_way;         // way that hit (valid in COMPARE result)

    wire [TAG_BITS-1:0] req_tag   = req_addr[ADDR_W-1:OFF_BITS+SET_BITS];
    wire [SET_BITS-1:0] req_set   = req_addr[OFF_BITS+SET_BITS-1:OFF_BITS];
    wire [WORD_OFF_W-1:0] req_word = req_addr[OFF_BITS-1:2];
    wire [ADDR_W-1:0]   block_base = req_addr & ~(BLOCK_BYTES-1);

    wire hit0 = vld_q0 && (tag_q0 == req_tag);
    wire hit1 = vld_q1 && (tag_q1 == req_tag);

    // ---- FSM state ----
    localparam S_IDLE       = 3'd0,
               S_COMPARE    = 3'd1,
               S_REFILL     = 3'd2,
               S_REFILL_GAP = 3'd3,
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
            dt_we0           <= 1'b0;
            dt_we1           <= 1'b0;
            tag_we0          <= 1'b0;
            tag_we1          <= 1'b0;
            vld_we0          <= 1'b0;
            vld_we1          <= 1'b0;
            lru_we           <= 1'b0;
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
            dt_we0  <= 1'b0;
            dt_we1  <= 1'b0;
            tag_we0 <= 1'b0;
            tag_we1 <= 1'b0;
            vld_we0 <= 1'b0;
            vld_we1 <= 1'b0;
            lru_we  <= 1'b0;

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
                if (hit0 || hit1) begin
                    // HIT
                    cnt_hit  <= cnt_hit + 32'd1;
                    hit_way  <= hit1;          // hit1 ? way1 : way0
                    lru_we   <= 1'b1;          // E-2: update LRU on every hit
                    lru_waddr<= req_set;
                    lru_wdata<= hit1;          // 0 -> way1 now LRU, 1 -> way0 LRU
                    if (!req_we) begin
                        cpu_rdata <= hit1 ? dt_q1 : dt_q0;
                        state     <= S_DONE;
                    end else begin
                        // write hit: update the cached word of the hitting way
                        if (hit1) dt_we1 <= 1'b1;
                        else      dt_we0 <= 1'b1;
                        dt_waddr <= {req_set, req_word};
                        dt_wdata <= req_wdata;
                        state    <= S_WRITE_THRU;
                    end
                end else begin
                    // MISS: replace the LRU way (lru_q read at accept edge)
                    cnt_miss   <= cnt_miss + 32'd1;
                    refill_way <= ~lru_q;    // bit 0 -> replace way1, bit 1 -> way0
                    if (!req_we) begin
                        // LRU updates only on an actual allocation (read miss);
                        // a write miss allocates nothing, so LRU is untouched
                        lru_we     <= 1'b1;
                        lru_waddr  <= req_set;
                        lru_wdata  <= ~lru_q;    // refilled way is now most recent
                        refill_cnt <= {REFILL_W{1'b0}};
                        state      <= S_REFILL;
                    end else begin
                        state <= S_WRITE_THRU;    // write miss: no allocate
                    end
                end
            end

            S_REFILL: begin
                cnt_stall_cycles <= cnt_stall_cycles + 32'd1;
                mem_we <= 1'b0;
                if (!mem_ready) begin
                    mem_req  <= 1'b1;
                    mem_addr <= block_base + {refill_cnt, 2'b00};
                end else begin
                    if (refill_way) dt_we1 <= 1'b1;
                    else            dt_we0 <= 1'b1;
                    dt_waddr <= {req_set, refill_cnt};
                    dt_wdata <= mem_rdata;
                    if (refill_cnt == req_word)
                        cpu_rdata <= mem_rdata;
                    if (refill_cnt == WORDS-1) begin
                        tag_waddr <= req_set;
                        tag_wdata <= req_tag;
                        if (refill_way) begin
                            tag_we1 <= 1'b1;
                            vld_we1 <= 1'b1;
                        end else begin
                            tag_we0 <= 1'b1;
                            vld_we0 <= 1'b1;
                        end
                        vld_waddr <= req_set;
                        vld_wdata <= 1'b1;
                        state     <= S_DONE;
                    end else begin
                        refill_cnt <= refill_cnt + 1'b1;
                        state      <= S_REFILL_GAP;
                    end
                end
            end

            S_REFILL_GAP: begin
                cnt_stall_cycles <= cnt_stall_cycles + 32'd1;
                mem_addr <= block_base + {refill_cnt, 2'b00};
                state    <= S_REFILL;
            end

            S_WRITE_THRU: begin
                cnt_stall_cycles <= cnt_stall_cycles + 32'd1;
                mem_we    <= 1'b1;
                mem_addr  <= req_addr;
                mem_wdata <= req_wdata;
                if (!mem_ready)
                    mem_req <= 1'b1;
                if (mem_ready)
                    state <= S_DONE;
            end

            S_DONE: begin
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
            endcase
        end
    end
endmodule
