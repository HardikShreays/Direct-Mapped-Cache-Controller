// main_memory_model.v -- behavioral word-wide memory (P1-4)
//
// Per-word handshake: mem_req/mem_we/mem_addr/mem_wdata in,
// mem_ready (one-cycle pulse) + mem_rdata out. Every word access takes
// MEM_LATENCY cycles (default 10).
//
// Init (per plan): mem[i] = i*4 + 32'hA5000000, i.e. the word at byte
// address A reads A + 32'hA5000000 until it is written.
module main_memory_model #(
    parameter MEM_LATENCY = 10,
    parameter ADDR_W      = 32,
    parameter MEM_WORDS   = 1 << 20          // covers byte addresses < 4MB
)(
    input  wire               clk,
    input  wire               rst,
    // memory-side interface of the cache
    input  wire               mem_req,
    input  wire               mem_we,
    input  wire [ADDR_W-1:0]  mem_addr,
    input  wire [31:0]        mem_wdata,
    output reg  [31:0]        mem_rdata,
    output reg                mem_ready
);
    localparam IDX_W = $clog2(MEM_WORDS);  // word index bits

    reg [31:0] mem [0:MEM_WORDS-1];
    reg        busy;
    reg [31:0] count;
    reg        lat_we;
    reg [ADDR_W-1:0] lat_addr;
    reg [31:0] lat_wdata;

    integer i;
    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1)
            mem[i] = i * 4 + 32'hA5000000;
        mem_rdata = 32'h0;
        mem_ready = 1'b0;
        busy      = 1'b0;
        count     = 32'h0;
    end

    always @(posedge clk) begin
        if (rst) begin
            busy      <= 1'b0;
            mem_ready <= 1'b0;
            count     <= 32'h0;
        end else begin
            if (mem_ready)
                mem_ready <= 1'b0;           // ready is a one-cycle pulse
            if (busy) begin
                if (count == MEM_LATENCY - 1) begin
                    mem_ready <= 1'b1;
                    if (lat_we)
                        mem[lat_addr[IDX_W+1:2]] <= lat_wdata;
                    else
                        mem_rdata <= mem[lat_addr[IDX_W+1:2]];
                    busy <= 1'b0;
                end else begin
                    count <= count + 1'b1;
                end
            end else if (!mem_ready && mem_req) begin
                // start a new transaction (ignore while a completion pulse
                // is still high, so no double-accept)
                busy      <= 1'b1;
                count     <= 32'h0;
                lat_addr  <= mem_addr;
                lat_we    <= mem_we;
                lat_wdata <= mem_wdata;
            end
        end
    end
endmodule
