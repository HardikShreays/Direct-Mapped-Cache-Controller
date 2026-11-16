// Behavioral word-wide memory for the cache memory-side interface.
//
// A request is accepted on a rising edge when mem_req is high and the model
// is idle.  The request fields are latched, and mem_ready pulses on the
// MEM_LATENCY-th rising edge after acceptance.  Read data is valid with that
// pulse.  Requests asserted while an access is pending are ignored.
module main_memory_model #(
    parameter integer MEM_LATENCY = 10,
    parameter integer ADDR_W      = 32,
    parameter integer MEM_WORDS   = 4096
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              mem_req,
    input  wire              mem_we,
    input  wire [ADDR_W-1:0] mem_addr,
    input  wire [31:0]       mem_wdata,
    output reg  [31:0]       mem_rdata,
    output reg               mem_ready
);
    reg [31:0] mem [0:MEM_WORDS-1];
    reg        busy;
    reg        accept_armed;
    reg        pending_we;
    reg [ADDR_W-1:0] pending_addr;
    reg [31:0] pending_wdata;
    integer cycles_left;
    integer i;

    initial begin
        if (MEM_LATENCY < 1) begin
            $display("ERROR main_memory_model: MEM_LATENCY must be at least 1");
            $finish(1);
        end
        for (i = 0; i < MEM_WORDS; i = i + 1)
            mem[i] = 32'hA5000000 + (i * 4);
        busy          = 1'b0;
        accept_armed  = 1'b1;
        mem_ready     = 1'b0;
        mem_rdata     = 32'b0;
        cycles_left   = 0;
        pending_we    = 1'b0;
        pending_addr  = {ADDR_W{1'b0}};
        pending_wdata = 32'b0;
    end

    always @(posedge clk) begin
        if (rst) begin
            busy        <= 1'b0;
            accept_armed <= 1'b1;
            mem_ready   <= 1'b0;
            cycles_left <= 0;
        end else begin
            mem_ready <= 1'b0;

            if (busy) begin
                if (cycles_left == 1) begin
                    if (pending_we)
                        mem[pending_addr >> 2] <= pending_wdata;
                    else
                        mem_rdata <= mem[pending_addr >> 2];
                    mem_ready   <= 1'b1;
                    busy        <= 1'b0;
                    cycles_left <= 0;
                end else begin
                    cycles_left <= cycles_left - 1;
                end
            end else if (!mem_req) begin
                // A fresh transaction requires mem_req to have gone low
                // since the previous acceptance.  The controller provides
                // this gap between refill words.
                accept_armed <= 1'b1;
            end else if (accept_armed) begin
                if (mem_addr[1:0] != 2'b00) begin
                    $display("ERROR main_memory_model: unaligned access at %h", mem_addr);
                    $finish(1);
                end
                if ((mem_addr >> 2) >= MEM_WORDS) begin
                    $display("ERROR main_memory_model: address %h is out of range", mem_addr);
                    $finish(1);
                end
                pending_we    <= mem_we;
                pending_addr  <= mem_addr;
                pending_wdata <= mem_wdata;
                cycles_left   <= MEM_LATENCY;
                busy          <= 1'b1;
                accept_armed  <= 1'b0;
            end
        end
    end
endmodule
