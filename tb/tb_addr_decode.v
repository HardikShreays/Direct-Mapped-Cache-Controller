// tb_addr_decode.v -- self-check for addr_decode (P1-2)
`timescale 1ns/1ps
module tb_addr_decode;
    reg  [31:0] addr;
    wire [3:0]  offset;
    wire [1:0]  word_off;
    wire [5:0]  index;
    wire [21:0] tag;

    integer errors = 0;

    addr_decode u_dut (
        .addr(addr), .offset(offset), .word_off(word_off),
        .index(index), .tag(tag)
    );

    task check;
        input [31:0] a;
        reg [3:0]  e_off;
        reg [1:0]  e_word;
        reg [5:0]  e_idx;
        reg [21:0] e_tag;
        begin
            addr = a;
            #1;
            e_off  = a[3:0];
            e_word = a[3:2];
            e_idx  = a[9:4];
            e_tag  = a[31:10];
            if (offset !== e_off || word_off !== e_word ||
                index !== e_idx || tag !== e_tag) begin
                errors = errors + 1;
                $display("FAIL: addr=%h off=%h(exp %h) word=%h(exp %h) idx=%h(exp %h) tag=%h(exp %h)",
                         a, offset, e_off, word_off, e_word, index, e_idx, tag, e_tag);
            end
        end
    endtask

    initial begin
        // hand-checked golden case: 0x00400C34 -> tag 0x1003, index 0x03,
        // word 1, offset 4
        addr = 32'h0040_0C34; #1;
        if (tag !== 22'h1003 || index !== 6'h03 ||
            word_off !== 2'd1 || offset !== 4'h4) begin
            errors = errors + 1;
            $display("FAIL: golden 0x00400C34 mismatch: tag=%h idx=%h word=%h off=%h",
                     tag, index, word_off, offset);
        end
        // formula checks over assorted addresses, including index boundaries
        check(32'h0000_0000);
        check(32'h0000_00FC);
        check(32'h0000_0100);
        check(32'hDEAD_BEEF);
        check(32'hA5A5_5A5A);
        check(32'hFFFF_FFFC);
        check(32'h0000_0410);
        check(32'h0004_0C34);

        if (errors == 0) $display("tb_addr_decode: PASS");
        else             $display("tb_addr_decode: FAIL (%0d errors)", errors);
        $finish(errors ? 1 : 0);
    end
endmodule
