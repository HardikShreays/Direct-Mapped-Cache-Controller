// Address field decoder for a 1 KiB, 16-byte-block direct-mapped cache.
module addr_decode (
    input  wire [31:0] addr,
    output wire [21:0] tag,
    output wire [5:0]  index,
    output wire [1:0]  word_sel,
    output wire [3:0]  byte_offset,
    output wire [31:0] block_base
);
    localparam integer ADDR_WIDTH        = 32;
    localparam integer TAG_WIDTH         = 22;
    localparam integer INDEX_WIDTH       = 6;
    localparam integer WORD_SELECT_WIDTH = 2;
    localparam integer OFFSET_WIDTH      = 4;

    assign tag         = addr[ADDR_WIDTH-1:INDEX_WIDTH+OFFSET_WIDTH];
    assign index       = addr[INDEX_WIDTH+OFFSET_WIDTH-1:OFFSET_WIDTH];
    assign word_sel    = addr[OFFSET_WIDTH-1:2];
    assign byte_offset = addr[OFFSET_WIDTH-1:0];
    assign block_base  = {addr[ADDR_WIDTH-1:OFFSET_WIDTH], {OFFSET_WIDTH{1'b0}}};
endmodule
