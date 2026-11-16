`timescale 1ns/1ps

module tb_tag_ram;
    reg clk;
    reg we;
    reg [5:0] index;
    reg [21:0] wdata;
    wire [21:0] rdata;
    integer i;
    integer errors;

    tag_ram dut (.clk(clk), .we(we), .index(index), .wdata(wdata), .rdata(rdata));

    always #5 clk = ~clk;

    task write_tag;
        input [5:0] write_index;
        input [21:0] write_data;
        begin
            @(negedge clk);
            we = 1'b1;
            index = write_index;
            wdata = write_data;
            @(posedge clk);
            #1;
        end
    endtask

    task check_tag;
        input [5:0] read_index;
        input [21:0] expected;
        begin
            @(negedge clk);
            we = 1'b0;
            index = read_index;
            #1;
            if (rdata !== expected) begin
                $display("FAIL: tag_ram index=%0d got=%h expected=%h", read_index, rdata, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        we = 1'b0;
        index = 6'd0;
        wdata = 22'd0;
        errors = 0;

        for (i = 0; i < 64; i = i + 1)
            write_tag(i[5:0], 22'h30000 + i);
        for (i = 0; i < 64; i = i + 1)
            check_tag(i[5:0], 22'h30000 + i);

        // A disabled write must leave the selected entry unchanged.
        @(negedge clk);
        we = 1'b0;
        index = 6'd17;
        wdata = 22'h3FFFF;
        @(posedge clk);
        #1;
        if (rdata !== 22'h30011) begin
            $display("FAIL: tag_ram write-enable low changed index 17 to %h", rdata);
            errors = errors + 1;
        end
        check_tag(6'd18, 22'h30012);

        if (errors == 0)
            $display("PASS: tag_ram");
        else
            $display("FAIL: tag_ram (%0d errors)", errors);
        $finish;
    end
endmodule
