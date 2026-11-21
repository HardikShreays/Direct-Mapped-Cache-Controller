// tb_valid_ram.v -- self-check for valid_ram (P1-2)
// Checks: reset clears all bits, write/read-back, and mid-run reset clears.
`timescale 1ns/1ps
module tb_valid_ram;
    reg        clk = 0, rst = 1, we = 0, wdata = 0;
    reg  [5:0] waddr, raddr;
    wire       q;

    integer errors = 0;

    valid_ram #(.N_LINES(64)) u_dut (
        .clk(clk), .rst(rst), .we(we), .waddr(waddr), .wdata(wdata),
        .raddr(raddr), .q(q)
    );

    always #5 clk = ~clk;

    task wr;
        input [5:0] a;
        input d;
        begin
            @(negedge clk); we = 1; waddr = a; wdata = d;
            @(negedge clk); we = 0;
        end
    endtask

    task rd;
        input [5:0] a;
        input exp_val;
        begin
            @(negedge clk); raddr = a;
            @(negedge clk); #1;
            if (q !== exp_val) begin
                errors = errors + 1;
                $display("FAIL: valid[%0d]=%b expected %b", a, q, exp_val);
            end
        end
    endtask

    initial begin
        raddr = 0;
        // 1. after reset all valid bits are 0
        repeat (2) @(negedge clk);
        rst = 0;
        rd(6'd0, 1'b0);
        rd(6'd63, 1'b0);
        // 2. set a few bits, read back
        wr(6'd7,  1'b1);
        wr(6'd40, 1'b1);
        rd(6'd7,  1'b1);
        rd(6'd40, 1'b1);
        rd(6'd8,  1'b0);   // neighbor still clear
        // 3. mid-run reset clears again
        @(negedge clk); rst = 1;
        repeat (2) @(negedge clk);
        rst = 0;
        rd(6'd7,  1'b0);
        rd(6'd40, 1'b0);

        if (errors == 0) $display("tb_valid_ram: PASS");
        else             $display("tb_valid_ram: FAIL (%0d errors)", errors);
        $finish(errors ? 1 : 0);
    end
endmodule
