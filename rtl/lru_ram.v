// lru_ram.v -- 1-bit LRU per set for the 2-way set-associative cache (E-2)
//
// Semantics: bit == 0 -> way 1 is the least-recently-used way (replace it);
//            bit == 1 -> way 0 is the least-recently-used way (replace it).
// On a hit or refill of way w, the bit is set so that the *other* way
// becomes LRU. Cleared to 0 on reset (an arbitrary but deterministic
// starting policy).
module lru_ram #(
    parameter N_SETS = 32,
    parameter AWIDTH = $clog2(N_SETS)
)(
    input  wire              clk,
    input  wire              rst,        // resets all LRU bits to 0
    input  wire              we,
    input  wire [AWIDTH-1:0] waddr,
    input  wire              wdata,
    // read port (synchronous: q valid one cycle after raddr)
    input  wire [AWIDTH-1:0] raddr,
    output reg               q
);
    reg bits [0:N_SETS-1];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < N_SETS; i = i + 1)
                bits[i] <= 1'b0;
            q <= 1'b0;
        end else begin
            if (we)
                bits[waddr] <= wdata;
            q <= bits[raddr];
        end
    end
endmodule
