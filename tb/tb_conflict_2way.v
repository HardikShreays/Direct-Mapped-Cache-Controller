// tb_conflict_2way.v -- regression case that 2-way must fix (E-4)
//
// Alternates reads between two addresses that collide in the direct-mapped
// cache (same index, different tags) but coexist in the 2-way design (same
// set, two ways):
//
//   A = 0x0400        B = A + CACHE_BYTES
//
// Direct-mapped : cold miss on A, then EVERY access misses (thrashing).
// 2-way         : cold misses on A and B, then every access hits.
//
// Also checks read data against the golden memory on both designs. The two
// caches are driven with the same read sequence, one after the other (each
// has its own cpu_req so a fast DUT cannot re-accept a pending request).
`timescale 1ns/1ps
module tb_conflict_2way;
    parameter CACHE_BYTES = 1024;
    parameter N_ACC       = 24;

    reg          clk = 0, rst = 1;
    reg          dm_req = 0, sa_req = 0;
    reg  [31:0]  cpu_addr = 0;
    wire [31:0]  dm_rdata, sa_rdata;
    wire         dm_ready, sa_ready;

    wire         dm_mem_req, dm_mem_we, sa_mem_req, sa_mem_we;
    wire [31:0]  dm_mem_addr, dm_mem_wdata, sa_mem_addr, sa_mem_wdata;
    wire [31:0]  dm_mem_rdata, sa_mem_rdata;
    wire         dm_mem_ready, sa_mem_ready;

    wire [31:0]  dm_cnt_a, dm_cnt_h, dm_cnt_m, dm_cnt_r, dm_cnt_w, dm_cnt_s;
    wire [31:0]  sa_cnt_a, sa_cnt_h, sa_cnt_m, sa_cnt_r, sa_cnt_w, sa_cnt_s;

    cache_top dm_dut (
        .clk(clk), .rst(rst),
        .cpu_req(dm_req), .cpu_we(1'b0), .cpu_addr(cpu_addr),
        .cpu_wdata(32'h0), .cpu_rdata(dm_rdata), .cpu_ready(dm_ready),
        .mem_req(dm_mem_req), .mem_we(dm_mem_we), .mem_addr(dm_mem_addr),
        .mem_wdata(dm_mem_wdata), .mem_rdata(dm_mem_rdata), .mem_ready(dm_mem_ready),
        .cnt_access(dm_cnt_a), .cnt_hit(dm_cnt_h), .cnt_miss(dm_cnt_m),
        .cnt_read(dm_cnt_r), .cnt_write(dm_cnt_w),
        .cnt_stall_cycles(dm_cnt_s));

    cache_top_2way sa_dut (
        .clk(clk), .rst(rst),
        .cpu_req(sa_req), .cpu_we(1'b0), .cpu_addr(cpu_addr),
        .cpu_wdata(32'h0), .cpu_rdata(sa_rdata), .cpu_ready(sa_ready),
        .mem_req(sa_mem_req), .mem_we(sa_mem_we), .mem_addr(sa_mem_addr),
        .mem_wdata(sa_mem_wdata), .mem_rdata(sa_mem_rdata), .mem_ready(sa_mem_ready),
        .cnt_access(sa_cnt_a), .cnt_hit(sa_cnt_h), .cnt_miss(sa_cnt_m),
        .cnt_read(sa_cnt_r), .cnt_write(sa_cnt_w),
        .cnt_stall_cycles(sa_cnt_s));

    main_memory_model #(.MEM_LATENCY(10)) dm_mem (
        .clk(clk), .rst(rst),
        .mem_req(dm_mem_req), .mem_we(dm_mem_we), .mem_addr(dm_mem_addr),
        .mem_wdata(dm_mem_wdata), .mem_rdata(dm_mem_rdata), .mem_ready(dm_mem_ready));

    main_memory_model #(.MEM_LATENCY(10)) sa_mem (
        .clk(clk), .rst(rst),
        .mem_req(sa_mem_req), .mem_we(sa_mem_we), .mem_addr(sa_mem_addr),
        .mem_wdata(sa_mem_wdata), .mem_rdata(sa_mem_rdata), .mem_ready(sa_mem_ready));

    always #5 clk = ~clk;

    reg [31:0] golden [0:1048576];
    integer i;
    integer errors = 0;
    reg [31:0] A, B;

    task do_read_dm;
        input [31:0] addr;
        begin
            @(negedge clk);
            cpu_addr = addr; dm_req = 1;
            @(posedge dm_ready);
            dm_req = 0;
            #1;
            if (dm_rdata !== golden[addr[21:2]]) begin
                errors = errors + 1;
                $display("FAIL DM read %h: got %h expected %h", addr, dm_rdata, golden[addr[21:2]]);
            end
        end
    endtask

    task do_read_sa;
        input [31:0] addr;
        begin
            @(negedge clk);
            cpu_addr = addr; sa_req = 1;
            @(posedge sa_ready);
            sa_req = 0;
            #1;
            if (sa_rdata !== golden[addr[21:2]]) begin
                errors = errors + 1;
                $display("FAIL 2W read %h: got %h expected %h", addr, sa_rdata, golden[addr[21:2]]);
            end
        end
    endtask

    initial begin
        for (i = 0; i < 1048576; i = i + 1)
            golden[i] = i * 4 + 32'hA5000000;

        A = 32'h0000_0400;                       // index 0x40, tag 0
        B = A + CACHE_BYTES;                     // same index, tag 1

        repeat (4) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        // same alternating sequence A,B,A,B,... through both caches
        for (i = 0; i < N_ACC; i = i + 1) begin
            do_read_dm((i % 2 == 0) ? A : B);
            do_read_sa((i % 2 == 0) ? A : B);
        end

        // verdicts
        if (dm_cnt_h !== 32'd0) begin
            errors = errors + 1;
            $display("FAIL DM: expected 0 hits on a 2-block thrash, got %0d", dm_cnt_h);
        end
        if (sa_cnt_h !== 32'd22) begin
            errors = errors + 1;
            $display("FAIL 2W: expected 22 hits (all but 2 cold misses), got %0d", sa_cnt_h);
        end else begin
            $display("2W conflict test: %0d accesses, %0d hits (DM got %0d hits)",
                     sa_cnt_a, sa_cnt_h, dm_cnt_h);
        end

        if (errors == 0) begin
            $display("CONFLICT TEST PASSED: 2-way fixes the direct-mapped thrash");
            $finish(0);
        end else begin
            $display("CONFLICT TEST FAILED (%0d errors)", errors);
            $finish(1);
        end
    end
endmodule
