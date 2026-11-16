`timescale 1ns/1ps

module tb_data_ram;
    reg clk;
    reg we;
    reg [5:0] index;
    reg [1:0] word_sel;
    reg [31:0] wdata;
    wire [31:0] rdata;
    integer i;
    integer errors;

    data_ram dut (
        .clk(clk), .we(we), .index(index), .word_sel(word_sel),
        .wdata(wdata), .rdata(rdata)
    );

    always #5 clk = ~clk;

    task write_word;
        input [5:0] write_index;
        input [1:0] write_word_sel;
        input [31:0] write_data;
        begin
            @(negedge clk);
            we = 1'b1;
            index = write_index;
            word_sel = write_word_sel;
            wdata = write_data;
            @(posedge clk);
            #1;
        end
    endtask

    task check_word;
        input [5:0] read_index;
        input [1:0] read_word_sel;
        input [31:0] expected;
        begin
            @(negedge clk);
            we = 1'b0;
            index = read_index;
            word_sel = read_word_sel;
            #1;
            if (rdata !== expected) begin
                $display("FAIL: data_ram index=%0d word_sel=%0d got=%h expected=%h", read_index, read_word_sel, rdata, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        we = 1'b0;
        index = 6'd0;
        word_sel = 2'd0;
        wdata = 32'd0;
        errors = 0;

        // Four separate words in a line must retain their individual values.
        write_word(6'd7, 2'd0, 32'h1111_0000);
        write_word(6'd7, 2'd1, 32'h2222_0001);
        write_word(6'd7, 2'd2, 32'h3333_0002);
        write_word(6'd7, 2'd3, 32'h4444_0003);
        check_word(6'd7, 2'd0, 32'h1111_0000);
        check_word(6'd7, 2'd1, 32'h2222_0001);
        check_word(6'd7, 2'd2, 32'h3333_0002);
        check_word(6'd7, 2'd3, 32'h4444_0003);

        // The same word position in a distinct line must not alias.
        write_word(6'd8, 2'd2, 32'hAAAA_0008);
        check_word(6'd8, 2'd2, 32'hAAAA_0008);
        check_word(6'd7, 2'd2, 32'h3333_0002);

        // A disabled write must not change an existing word.
        @(negedge clk);
        we = 1'b0;
        index = 6'd7;
        word_sel = 2'd1;
        wdata = 32'hDEAD_BEEF;
        @(posedge clk);
        #1;
        if (rdata !== 32'h2222_0001) begin
            $display("FAIL: data_ram write-enable low changed selected word to %h", rdata);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: data_ram");
        else
            $display("FAIL: data_ram (%0d errors)", errors);
        $finish;
    end
endmodule
