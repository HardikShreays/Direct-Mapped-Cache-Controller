// Data store: 64 cache lines, each containing four 32-bit words.
module data_ram (
    input  wire        clk,
    input  wire        we,
    input  wire [5:0]  index,
    input  wire [1:0]  word_sel,
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);
    localparam integer NUM_LINES      = 64;
    localparam integer WORDS_PER_LINE = 4;
    localparam integer DATA_WIDTH     = 32;

    reg [DATA_WIDTH-1:0] mem [0:NUM_LINES*WORDS_PER_LINE-1];

    always @(posedge clk) begin
        if (we)
            mem[{index, word_sel}] <= wdata;
    end

    assign rdata = mem[{index, word_sel}];
endmodule
