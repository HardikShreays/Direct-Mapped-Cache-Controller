// tb_data_ram.v -- self-check for data_ram (P1-2)
`timescale 1ns/1ps
module tb_data_ram;
    reg         clk = 0, we = 0;
    reg  [7:0]  waddr, raddr;
    reg  [31:0] wdata;
    wire [31:0] q;

    integer errors = 0;

    data_ram #(.N_LINES(64), .WORDS(4)) u_dut (
        .clk(clk), .we(we), .waddr(waddr), .wdata(wdata),
        .raddr(raddr), .q(q)
    );

    always #5 clk = ~clk;

    task wr;
        input [7:0] a;
        input [31:0] d;
        begin
            @(negedge clk); we = 1; waddr = a; wdata = d;
            @(negedge clk); we = 0;
        end
    endtask

    task rd;
        input [7:0] a;
        input [31:0] exp_val;
        begin
            @(negedge clk); raddr = a;
            @(negedge clk); #1;
            if (q !== exp_val) begin
                errors = errors + 1;
                $display("FAIL: data[%0d]=%h expected %h", a, q, exp_val);
            end
        end
    endtask

    initial begin
        raddr = 0;
        // refill-like pattern: 4 words of one block (entries 4..7 = line 1)
        wr(8'd4, 32'h11111111);
        wr(8'd5, 32'h22222222);
        wr(8'd6, 32'h33333333);
        wr(8'd7, 32'h44444444);
        rd(8'd4, 32'h11111111);
        rd(8'd5, 32'h22222222);
        rd(8'd6, 32'h33333333);
        rd(8'd7, 32'h44444444);
        // word update inside a block (write-hit behavior)
        wr(8'd5, 32'hDEADBEEF);
        rd(8'd5, 32'hDEADBEEF);
        rd(8'd6, 32'h33333333);   // neighbors untouched
        // last entry
        wr(8'd255, 32'hCAFEBABE);
        rd(8'd255, 32'hCAFEBABE);
        // Keep the target branch's separate-line alias check.
        wr({6'd7, 2'd2}, 32'h77770002);
        wr({6'd8, 2'd2}, 32'h88880002);
        rd({6'd7, 2'd2}, 32'h77770002);
        rd({6'd8, 2'd2}, 32'h88880002);

        if (errors == 0) $display("tb_data_ram: PASS");
        else             $display("tb_data_ram: FAIL (%0d errors)", errors);
        $finish(errors ? 1 : 0);
    end
endmodule
