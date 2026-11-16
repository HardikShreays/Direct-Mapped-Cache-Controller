// addr_decode.v -- combinational address split (P1-2)
//
// Frozen spec: 32-bit address, 16B blocks, 1KB cache.
//   offset  [3:0]     -> OFF_BITS   (word select = offset[3:2])
//   index   [9:4]     -> IDX_BITS
//   tag     [31:10]   -> TAG_BITS
//
// All fields are derived from CACHE_BYTES / BLOCK_BYTES with $clog2 so the
// same module works for other geometries (Phase A parameterization).
module addr_decode #(
    parameter ADDR_W      = 32,
    parameter CACHE_BYTES = 1024,
    parameter BLOCK_BYTES = 16,
    parameter OFF_BITS    = $clog2(BLOCK_BYTES),
    parameter N_LINES     = CACHE_BYTES / BLOCK_BYTES,
    parameter IDX_BITS    = $clog2(N_LINES),
    parameter TAG_BITS    = ADDR_W - OFF_BITS - IDX_BITS,
    parameter WORD_OFF_W  = OFF_BITS - 2   // bits above the 4B word granularity
)(
    input  wire [ADDR_W-1:0]     addr,
    output wire [OFF_BITS-1:0]   offset,    // byte within block
    output wire [WORD_OFF_W-1:0] word_off,  // word within block
    output wire [IDX_BITS-1:0]   index,     // line number
    output wire [TAG_BITS-1:0]   tag
);
    assign offset   = addr[OFF_BITS-1:0];
    assign word_off = addr[OFF_BITS-1:2];
    assign index    = addr[OFF_BITS+IDX_BITS-1:OFF_BITS];
    assign tag      = addr[ADDR_W-1:OFF_BITS+IDX_BITS];
endmodule
