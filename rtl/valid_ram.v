// valid_ram.v -- one valid bit per line, cleared on reset (P1-2)
module valid_ram #(
    parameter N_LINES = 64,
    parameter AWIDTH  = $clog2(N_LINES)
)(
    input  wire              clk,
    input  wire              rst,        // clears every valid bit
    // write port
    input  wire              we,
    input  wire [AWIDTH-1:0] waddr,
    input  wire              wdata,
    // read port (synchronous: q valid one cycle after raddr)
    input  wire [AWIDTH-1:0] raddr,
    output reg               q
);
    reg bits [0:N_LINES-1];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < N_LINES; i = i + 1)
                bits[i] <= 1'b0;
            q <= 1'b0;
        end else begin
            if (we)
                bits[waddr] <= wdata;
            q <= bits[raddr];
        end
    end
endmodule
