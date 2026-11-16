// data_ram.v -- cache data array: N_LINES lines x WORDS 32-bit words (P1-2)
// Addressed by {index, word_off}. Synchronous write, synchronous read.
module data_ram #(
    parameter N_LINES = 64,
    parameter WORDS   = 4,                // words (32-bit) per block
    parameter DEPTH   = N_LINES * WORDS,
    parameter AWIDTH  = $clog2(DEPTH)
)(
    input  wire               clk,
    // write port
    input  wire               we,
    input  wire [AWIDTH-1:0]  waddr,
    input  wire [31:0]        wdata,
    // read port (synchronous: q valid one cycle after raddr)
    input  wire [AWIDTH-1:0]  raddr,
    output reg  [31:0]        q
);
    reg [31:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
        q <= mem[raddr];
    end
endmodule
