// tag_ram.v -- TAG_BITS-wide tag per line (P1-2)
// No reset needed: a line's tag is only meaningful when its valid bit is set.
module tag_ram #(
    parameter N_LINES = 64,
    parameter DWIDTH  = 22,               // = TAG_BITS of the address split
    parameter AWIDTH  = $clog2(N_LINES)
)(
    input  wire               clk,
    // write port
    input  wire               we,
    input  wire [AWIDTH-1:0]  waddr,
    input  wire [DWIDTH-1:0]  wdata,
    // read port (synchronous: q valid one cycle after raddr)
    input  wire [AWIDTH-1:0]  raddr,
    output reg  [DWIDTH-1:0]  q
);
    reg [DWIDTH-1:0] tags [0:N_LINES-1];

    always @(posedge clk) begin
        if (we)
            tags[waddr] <= wdata;
        q <= tags[raddr];
    end
endmodule
