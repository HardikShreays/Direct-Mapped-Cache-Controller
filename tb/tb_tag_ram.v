// tb_tag_ram.v -- self-check for tag_ram (P1-2)
`timescale 1ns/1ps
module tb_tag_ram;
    reg         clk = 0, we = 0;
    reg  [5:0]  waddr, raddr;
    reg  [21:0] wdata;
    wire [21:0] q;

    integer errors = 0;

    tag_ram #(.N_LINES(64), .DWIDTH(22)) u_dut (
        .clk(clk), .we(we), .waddr(waddr), .wdata(wdata),
        .raddr(raddr), .q(q)
    );

    always #5 clk = ~clk;

    task wr;
        input [5:0] a;
        input [21:0] d;
        begin
            @(negedge clk); we = 1; waddr = a; wdata = d;
            @(negedge clk); we = 0;
        end
    endtask

    task rd;
        input [5:0] a;
        input [21:0] exp_val;
        begin
            @(negedge clk); raddr = a;
            @(negedge clk); #1;
            if (q !== exp_val) begin
                errors = errors + 1;
                $display("FAIL: tag[%0d]=%h expected %h", a, q, exp_val);
            end
        end
    endtask

    initial begin
        raddr = 0;
        wr(6'd5,  22'h000ABC);
        wr(6'd63, 22'h3FFFFF);
        wr(6'd0,  22'h000001);
        rd(6'd5,  22'h000ABC);
        rd(6'd63, 22'h3FFFFF);
        rd(6'd0,  22'h000001);
        // untouched line was written? no -- write then read to stay X-free
        wr(6'd1,  22'h155555);
        rd(6'd1,  22'h155555);
        // overwrite check
        wr(6'd5,  22'h0F0F0F);
        rd(6'd5,  22'h0F0F0F);

        if (errors == 0) $display("tb_tag_ram: PASS");
        else             $display("tb_tag_ram: FAIL (%0d errors)", errors);
        $finish(errors ? 1 : 0);
    end
endmodule
