// Tag store: one 22-bit tag for each of the 64 cache lines.
module tag_ram (
    input  wire        clk,
    input  wire        we,
    input  wire [5:0]  index,
    input  wire [21:0] wdata,
    output wire [21:0] rdata
);
    localparam integer NUM_LINES = 64;
    localparam integer TAG_WIDTH = 22;

    reg [TAG_WIDTH-1:0] mem [0:NUM_LINES-1];

    always @(posedge clk) begin
        if (we)
            mem[index] <= wdata;
    end

    assign rdata = mem[index];
endmodule
