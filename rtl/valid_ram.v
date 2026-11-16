// Valid-bit store for the 64 cache lines.
module valid_ram (
    input  wire       clk,
    input  wire       rst,
    input  wire       we,
    input  wire [5:0] index,
    input  wire       wdata,
    output wire       rdata
);
    localparam integer NUM_LINES = 64;

    reg [NUM_LINES-1:0] valid_bits;
    integer i;

    always @(posedge clk) begin
        // Power-up contents are unknown, so no line may count as a hit before it is refilled.
        if (rst) begin
            for (i = 0; i < NUM_LINES; i = i + 1)
                valid_bits[i] <= 1'b0;
        end else if (we) begin
            valid_bits[index] <= wdata;
        end
    end

    assign rdata = valid_bits[index];
endmodule
