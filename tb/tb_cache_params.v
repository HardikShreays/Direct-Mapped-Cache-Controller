// tb_cache_params.v -- directed tests for arbitrary cache geometries (Gate A)
//
// Same directed sequence as tb_cache_basic, but every address is derived from
// the CACHE_BYTES / BLOCK_BYTES parameters, so the same testbench verifies the
// parameterized design (A-4). Compile-time overrides, e.g.:
//
//   iverilog -g2012 -Ptb_cache_params.CACHE_BYTES=2048 \
//            -Ptb_cache_params.BLOCK_BYTES=32 ...
//
// Directed tests:
//   T1  cold read miss + full-block refill
//   T2  read hit (same address)
//   T3  different word, same block -> hit
//   T4  same-index conflict miss (tag = base tag + CACHE_BYTES)
//   T5  evicted line misses again
//   T6  write miss -> memory only, no allocate
//   T7  write hit -> cache word AND memory updated (read-after-write)
//   T8  mid-run reset -> valid bits cleared, line misses again
//
// Assertion-style checks (B-4) are always active:
//   - cpu_ready pulses exactly once per request, never two cycles in a row
//   - valid bit never set before the last refill word completes
//   - no memory write is ever issued for a read request
//   - cpu_ready is only asserted in the DONE state
`timescale 1ns/1ps
module tb_cache_params #(
    parameter CACHE_BYTES = 1024,
    parameter BLOCK_BYTES = 16
);
    localparam WORDS = BLOCK_BYTES / 4;

    reg         clk = 0, rst = 1;
    reg         cpu_req = 0, cpu_we = 0;
    reg  [31:0] cpu_addr = 0, cpu_wdata = 0;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;

    wire        mem_req, mem_we;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire        mem_ready;

    wire [31:0] cnt_access, cnt_hit, cnt_miss, cnt_read, cnt_write, cnt_stall_cycles;

    cache_top #(
        .CACHE_BYTES (CACHE_BYTES),
        .BLOCK_BYTES (BLOCK_BYTES)
    ) dut (
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

    // ---- golden memory mirror (byte addresses < 4MB) ----
    reg [31:0] golden [0:1048575];
    integer i;

    // ---- bookkeeping ----
    integer errors = 0;
    integer exp_access = 0, exp_hit = 0, exp_miss = 0;
    integer exp_read = 0, exp_write = 0;

    // ---- assertion monitors (B-4) ----
    reg ready_prev = 0;
    reg [2:0]  prev_state = 3'd0;
    reg [31:0] prev_refill_cnt = 0;
    localparam [2:0] S_REFILL = 3'd2, S_DONE = 3'd5;
    always @(negedge clk) begin
        if (!rst) begin
            if (cpu_ready === 1'b1 && ready_prev) begin
                errors = errors + 1;
                $display("FAIL ASSERT: cpu_ready high for 2+ consecutive cycles");
            end
            if (cpu_ready === 1'b1 && dut.u_ctrl.state !== dut.u_ctrl.S_DONE) begin
                errors = errors + 1;
                $display("FAIL ASSERT: cpu_ready outside DONE state");
            end
            // vld_we is registered: visible in the cycle after the final
            // refill word was accepted (state already advanced to DONE)
            if (dut.u_ctrl.vld_we === 1'b1 &&
                !(prev_state == S_REFILL && prev_refill_cnt == WORDS-1)) begin
                errors = errors + 1;
                $display("FAIL ASSERT: valid bit set outside final refill word (prev_state=%0d prev_cnt=%0d)",
                         prev_state, prev_refill_cnt);
            end
            // memory writes only for write requests (no write on read hit)
            if (dut.mem_we === 1'b1 && dut.u_ctrl.req_we !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL ASSERT@%0t: mem write on read (state=%0d req_we=%b req_addr=%h)",
                         $time, dut.u_ctrl.state, dut.u_ctrl.req_we, dut.u_ctrl.req_addr);
            end
        end
        ready_prev <= (cpu_ready === 1'b1);
        prev_state      <= dut.u_ctrl.state;
        prev_refill_cnt <= dut.u_ctrl.refill_cnt;
    end

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
            if (cpu_rdata !== golden[addr[21:2]]) begin
                errors = errors + 1;
                $display("FAIL read %h: got %h expected %h (hit_exp=%b)",
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
        end
    endtask

    task check_counters;
        input [127:0] label;
        begin
            if (cnt_access !== exp_access[31:0] || cnt_hit !== exp_hit[31:0] ||
                cnt_miss !== exp_miss[31:0] || cnt_read !== exp_read[31:0] ||
                cnt_write !== exp_write[31:0]) begin
                errors = errors + 1;
                $display("FAIL counters after %0s: access=%0d(exp %0d) hit=%0d(exp %0d) miss=%0d(exp %0d) read=%0d(exp %0d) write=%0d(exp %0d)",
                         label, cnt_access, exp_access, cnt_hit, exp_hit,
                         cnt_miss, exp_miss, cnt_read, exp_read, cnt_write, exp_write);
            end
        end
    endtask

    initial begin
        for (i = 0; i < 1048576; i = i + 1)
            golden[i] = i * 4 + 32'hA5000000;

        repeat (4) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        // T1: cold read miss
        do_read(32'h0000_0100, 0);
        // T2: read hit
        do_read(32'h0000_0100, 1);
        // T3: different word of the same block -> hit
        do_read(32'h0000_0104, 1);
        if (WORDS > 2) do_read(32'h0000_010C, 1);
        // T4: conflict miss -- same index, different tag (addr + CACHE_BYTES)
        do_read(32'h0000_0100 + CACHE_BYTES, 0);
        // T5: evicted line misses again
        do_read(32'h0000_0100, 0);
        check_counters("T5 conflict+eviction");

        // T6: write miss -> memory only, no allocate
        do_write(32'h0000_0100 + CACHE_BYTES, 32'hDEADBEEF, 0);
        do_read(32'h0000_0100 + CACHE_BYTES, 0);   // still misses: nothing allocated
        do_read(32'h0000_0104 + CACHE_BYTES, 1);   // block now cached, neighbor hits

        // T7: write hit + read-after-write (re-warm base line first)
        do_read(32'h0000_0100, 0);
        do_write(32'h0000_0100, 32'h12345678, 1);
        do_read(32'h0000_0100, 1);
        check_counters("T7 write hit path");

        // T8: mid-run reset; memory keeps write-through data
        @(negedge clk); rst = 1;
        repeat (3) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);
        exp_access = 0; exp_hit = 0; exp_miss = 0;
        exp_read = 0; exp_write = 0;
        do_read(32'h0000_0100, 0);                 // misses again after reset
        if (cpu_rdata !== 32'h12345678) begin
            errors = errors + 1;
            $display("FAIL T8: memory lost write-through data: %h", cpu_rdata);
        end
        check_counters("T8 post-reset");

        if (errors == 0) begin
            $display("ALL PARAM TESTS PASSED (%0dB cache / %0dB block)",
                     CACHE_BYTES, BLOCK_BYTES);
            $finish(0);
        end else begin
            $display("PARAM TESTS FAILED (%0d errors) for %0dB cache / %0dB block",
                     errors, CACHE_BYTES, BLOCK_BYTES);
            $finish(1);
        end
    end
endmodule
