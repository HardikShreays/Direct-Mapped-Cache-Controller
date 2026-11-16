`timescale 1ns/1ps

module tb_addr_decode;
    reg  [31:0] addr;
    wire [21:0] tag;
    wire [5:0]  index;
    wire [1:0]  word_sel;
    wire [3:0]  byte_offset;
    wire [31:0] block_base;
    integer errors;

    addr_decode dut (
        .addr(addr), .tag(tag), .index(index), .word_sel(word_sel),
        .byte_offset(byte_offset), .block_base(block_base)
    );

    task check_address;
        input [31:0] value;
        reg [21:0] expected_tag;
        reg [5:0]  expected_index;
        reg [1:0]  expected_word_sel;
        reg [3:0]  expected_byte_offset;
        reg [31:0] expected_block_base;
        begin
            addr = value;
            #1;
            expected_tag         = value[31:10];
            expected_index       = value[9:4];
            expected_word_sel    = value[3:2];
            expected_byte_offset = value[3:0];
            expected_block_base  = {value[31:4], 4'b0000};
            if ((tag !== expected_tag) || (index !== expected_index) ||
                (word_sel !== expected_word_sel) ||
                (byte_offset !== expected_byte_offset) ||
                (block_base !== expected_block_base)) begin
                $display("FAIL: addr_decode addr=%h got tag=%h index=%h word_sel=%h byte_offset=%h block_base=%h", value, tag, index, word_sel, byte_offset, block_base);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        check_address(32'h0000_0000);
        check_address(32'hFFFF_FFFF);
        check_address(32'h0000_0010);
        check_address(32'h0000_03FC);
        check_address(32'h0000_0400);
        check_address(32'hA500_0000);
        check_address(32'h1234_5678);
        check_address(32'hDEAD_BEEF);

        if (errors == 0)
            $display("PASS: addr_decode");
        else
            $display("FAIL: addr_decode (%0d errors)", errors);
        $finish;
    end
endmodule
