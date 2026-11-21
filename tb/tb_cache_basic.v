// tb_cache_basic.v -- directed tests for the direct-mapped cache (P1-4)
//
// Directed tests:
//   T1  cold read miss + 4-word refill
//   T2  read hit (same address)
//   T3  different offset, same block -> hit
//   T4  same-index conflict miss (different tag)
//   T5  evicted line misses again
//   T6  write miss -> memory only, no allocate (read back misses)
//   T7  write hit -> cache word AND memory updated (read-after-write)
//   T8  mid-run reset -> valid bits cleared, line misses again
//
// Golden memory mirrors every write-through (the behavioral memory model
// starts as mem[i] = i*4 + A5000000).
// On success prints ALL TESTS PASSED and dumps sim/cache.vcd showing
// miss -> 4-word refill -> hit.
`timescale 1ns/1ps
module tb_cache_basic;
    reg         clk = 0, rst = 1;
    reg         cpu_req = 0, cpu_we = 0;
    reg  [31:0] cpu_addr = 0, cpu_wdata = 0;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;

    wire        mem_req, mem_we;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire        mem_ready;

    wire [31:0] cnt_access, cnt_hit, cnt_miss, cnt_read, cnt_write, cnt_stall_cycles;

    cache_top dut (
        .clk(clk), .rst(rst),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready),
        .cnt_access(cnt_access), .cnt_hit(cnt_hit), .cnt_miss(cnt_miss),
        .cnt_read(cnt_read), .cnt_write(cnt_write),
        .cnt_stall_cycles(cnt_stall_cycles)
    );

    main_memory_model #(.MEM_LATENCY(10)) u_mem (
        .clk(clk), .rst(rst),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    always #5 clk = ~clk;

    // ---- golden memory mirror ----
    reg [31:0] golden [0:262143];   // byte addresses < 1MB
    integer i;

    // ---- bookkeeping ----
    integer errors = 0;
    integer exp_access = 0, exp_hit = 0, exp_miss = 0;
    integer exp_read = 0, exp_write = 0;
    integer ready_pulses = 0, exp_pulses = 0;

    // cpu_ready must pulse exactly once per request (guard + count in tasks)
    reg ready_prev = 0;
    always @(posedge clk) begin
        if (!rst && cpu_ready === 1'b1 && ready_prev) begin
            errors = errors + 1;
            $display("FAIL: cpu_ready high for 2+ consecutive cycles");
        end
        ready_prev <= (cpu_ready === 1'b1);
    end

    // ---- driver tasks (drive on negedge, sample on ready) ----
    task do_read;
        input [31:0] addr;
        input expect_hit;
        begin
            @(negedge clk);
            cpu_addr = addr; cpu_we = 0; cpu_req = 1;
            @(posedge cpu_ready);
            cpu_req = 0;
            #1;
            exp_access = exp_access + 1;
            exp_read   = exp_read + 1;
            if (expect_hit) exp_hit  = exp_hit + 1;
            else            exp_miss = exp_miss + 1;
            ready_pulses = ready_pulses + 1;
            exp_pulses   = exp_pulses + 1;
            if (cpu_rdata !== golden[addr[21:2]]) begin
                errors = errors + 1;
                $display("FAIL T? read %h: got %h expected %h (hit_exp=%b)",
                         addr, cpu_rdata, golden[addr[21:2]], expect_hit);
            end
        end
    endtask

    task do_write;
        input [31:0] addr;
        input [31:0] data;
        input expect_hit;
        begin
            @(negedge clk);
            cpu_addr = addr; cpu_wdata = data; cpu_we = 1; cpu_req = 1;
            @(posedge cpu_ready);
            cpu_req = 0; cpu_we = 0;
            #1;
            golden[addr[21:2]] = data;    // write-through reaches memory
            exp_access = exp_access + 1;
            exp_write  = exp_write + 1;
            if (expect_hit) exp_hit  = exp_hit + 1;
            else            exp_miss = exp_miss + 1;
            ready_pulses = ready_pulses + 1;
            exp_pulses   = exp_pulses + 1;
        end
    endtask

    task check_counters;
        input [127:0] label;
        begin
            if (cnt_access !== exp_access[31:0] || cnt_hit !== exp_hit[31:0] ||
                cnt_miss !== exp_miss[31:0] || cnt_read !== exp_read[31:0] ||
                cnt_write !== exp_write[31:0] || ready_pulses !== exp_pulses) begin
                errors = errors + 1;
                $display("FAIL counters after %0s: access=%0d(exp %0d) hit=%0d(exp %0d) miss=%0d(exp %0d) read=%0d(exp %0d) write=%0d(exp %0d) pulses=%0d(exp %0d)",
                         label, cnt_access, exp_access, cnt_hit, exp_hit,
                         cnt_miss, exp_miss, cnt_read, exp_read,
                         cnt_write, exp_write, ready_pulses, exp_pulses);
            end
        end
    endtask

    // ---- waveform ----
    initial begin
        $dumpfile("sim/cache.vcd");
        $dumpvars(0, tb_cache_basic);
    end

    initial begin
        for (i = 0; i < 262144; i = i + 1)
            golden[i] = i * 4 + 32'hA5000000;

        // reset
        repeat (4) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        // T1: cold read miss, block 0x10-0x1F refilled
        do_read(32'h0000_0010, 0);
        check_counters("T1 cold miss");

        // T2: read hit, same address
        do_read(32'h0000_0010, 1);

        // T3: different words of the same block -> hits
        do_read(32'h0000_0014, 1);
        do_read(32'h0000_001C, 1);

        // T4: conflict miss -- 0x410 maps to the same index as 0x10
        do_read(32'h0000_0410, 0);

        // T5: 0x10 was evicted by T4 -> miss again
        do_read(32'h0000_0010, 0);
        check_counters("T5 conflict+eviction");

        // T6: write MISS at 0x410 (line currently holds 0x10's tag):
        //     write-through to memory, NO allocate
        do_write(32'h0000_0410, 32'hDEADBEEF, 0);
        do_read(32'h0000_0410, 0);          // still misses: nothing allocated
        do_read(32'h0000_0414, 1);          // block now cached, neighbors hit

        // T7: write HIT at 0x10. 0x10 was evicted by T6's read refill,
        // so re-warm it first, then write hit, then read-after-write.
        do_read(32'h0000_0010, 0);          // miss: re-warms 0x10's block
        do_write(32'h0000_0010, 32'h12345678, 1);
        do_read(32'h0000_0010, 1);          // read-after-write: new data
        check_counters("T7 write hit path");

        // T8: mid-run reset clears valid bits; memory keeps write-through data
        @(negedge clk); rst = 1;
        repeat (3) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);
        exp_access = 0; exp_hit = 0; exp_miss = 0;
        exp_read = 0; exp_write = 0; exp_pulses = 0;
        ready_pulses = 0;
        do_read(32'h0000_0010, 0);          // misses again after reset
        if (cpu_rdata !== 32'h12345678) begin
            errors = errors + 1;
            $display("FAIL T8: memory lost write-through data: %h", cpu_rdata);
        end
        check_counters("T8 post-reset");

        // ---- verdict ----
        if (errors == 0) begin
            $display("ALL TESTS PASSED");
            $display("counters: access=%0d hit=%0d miss=%0d read=%0d write=%0d stall=%0d",
                     cnt_access, cnt_hit, cnt_miss, cnt_read, cnt_write, cnt_stall_cycles);
        end else begin
            $display("TESTS FAILED (%0d errors)", errors);
        end
        $finish(errors ? 1 : 0);
    end
endmodule
