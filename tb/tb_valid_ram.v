`timescale 1ns/1ps

module tb_valid_ram;
    reg clk;
    reg rst;
    reg we;
    reg [5:0] index;
    reg wdata;
    wire rdata;
    integer i;
    integer errors;

    valid_ram dut (.clk(clk), .rst(rst), .we(we), .index(index), .wdata(wdata), .rdata(rdata));

    always #5 clk = ~clk;

    task check_valid;
        input [5:0] read_index;
        input expected;
        begin
            index = read_index;
            #1;
            if (rdata !== expected) begin
                $display("FAIL: valid_ram index=%0d got=%b expected=%b", read_index, rdata, expected);
                errors = errors + 1;
            end
        end
    endtask

    task write_valid;
        input [5:0] write_index;
        input write_data;
        begin
            @(negedge clk);
            rst = 1'b0;
            we = 1'b1;
            index = write_index;
            wdata = write_data;
            @(posedge clk);
            #1;
            we = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        we = 1'b0;
        index = 6'd0;
        wdata = 1'b0;
        errors = 0;

        @(posedge clk);
        #1;
        rst = 1'b0;
        for (i = 0; i < 64; i = i + 1)
            check_valid(i[5:0], 1'b0);

        write_valid(6'd2, 1'b1);
        write_valid(6'd19, 1'b1);
        write_valid(6'd63, 1'b1);
        for (i = 0; i < 64; i = i + 1) begin
            if ((i == 2) || (i == 19) || (i == 63))
                check_valid(i[5:0], 1'b1);
            else
                check_valid(i[5:0], 1'b0);
        end

        // A disabled write must not set an invalid line.
        @(negedge clk);
        we = 1'b0;
        index = 6'd20;
        wdata = 1'b1;
        @(posedge clk);
        #1;
        check_valid(6'd20, 1'b0);

        // Reset takes priority over a simultaneous write.
        @(negedge clk);
        rst = 1'b1;
        we = 1'b1;
        index = 6'd7;
        wdata = 1'b1;
        @(posedge clk);
        #1;
        rst = 1'b0;
        we = 1'b0;
        for (i = 0; i < 64; i = i + 1)
            check_valid(i[5:0], 1'b0);

        if (errors == 0)
            $display("PASS: valid_ram");
        else
            $display("FAIL: valid_ram (%0d errors)", errors);
        $finish;
    end
endmodule
