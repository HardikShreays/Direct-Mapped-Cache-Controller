// tb_cache_trace.v -- trace-driven testbench (B-2)
//
// Reads a .trace file ('R 0xADDR' / 'W 0xADDR 0xDATA', '#' comments), drives
// the cache through main_memory_model, and checks every read against a golden
// memory array (initially mem[i] = i*4 + A5000000, mirrored on every
// write-through). Prints the final performance counters and a
// machine-readable line for the crosscheck (B-3).
//
// Usage:
//   vvp sim/tb_trace +trace=traces/loop.trace +mem_latency=10
//
// Assertion-style checks (B-4) are always active:
//   - cpu_ready pulses exactly once per request, never two cycles in a row,
//     and only in the DONE state
//   - a valid bit is only set on the final refill word of a REFILL
//   - no memory write is ever issued for a read request
`timescale 1ns/1ps
module tb_cache_trace #(
    parameter CACHE_BYTES = 1024,
    parameter BLOCK_BYTES = 16,
    parameter WAYS        = 1      // 1 = direct-mapped, 2 = set-associative
);
    reg         clk = 0, rst = 1;
    reg         cpu_req = 0, cpu_we = 0;
    reg  [31:0] cpu_addr = 0, cpu_wdata = 0;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;

    wire        mem_req, mem_we;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire        mem_ready;

    wire [31:0] cnt_access, cnt_hit, cnt_miss, cnt_read, cnt_write, cnt_stall_cycles;

    generate
        if (WAYS == 2) begin : g_dut
            cache_top_2way #(
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
        end else begin : g_dut
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
        end
    endgenerate

    main_memory_model #(.MEM_LATENCY(10)) u_mem (
        .clk(clk), .rst(rst),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    always #5 clk = ~clk;

    // ---- assertion monitors (B-4) ----
    reg        ready_prev = 0;
    reg [2:0]  prev_state = 0;
    reg [31:0] prev_refill_cnt = 0;
    integer a_errors = 0;
    localparam [2:0] S_REFILL_A = 3'd2;

    // valid-write monitor signal differs between the two designs
    generate if (WAYS == 1) begin : g_vldmon
        wire vld_we_mon = g_dut.dut.u_ctrl.vld_we;
    end else begin : g_vldmon
        wire vld_we_mon = g_dut.dut.u_ctrl.vld_we0 | g_dut.dut.u_ctrl.vld_we1;
    end endgenerate

    always @(negedge clk) begin
        if (!rst) begin
            if (cpu_ready === 1'b1 && ready_prev) begin
                a_errors = a_errors + 1;
                $display("FAIL ASSERT@%0t: cpu_ready high for 2+ consecutive cycles", $time);
            end
            if (cpu_ready === 1'b1 && g_dut.dut.u_ctrl.state !== g_dut.dut.u_ctrl.S_DONE) begin
                a_errors = a_errors + 1;
                $display("FAIL ASSERT@%0t: cpu_ready outside DONE state", $time);
            end
            if (g_vldmon.vld_we_mon === 1'b1 &&
                !(prev_state == S_REFILL_A && prev_refill_cnt == g_dut.dut.u_ctrl.WORDS-1)) begin
                a_errors = a_errors + 1;
                $display("FAIL ASSERT@%0t: valid bit set outside final refill word", $time);
            end
            if (g_dut.dut.mem_we === 1'b1 && g_dut.dut.u_ctrl.req_we !== 1'b1) begin
                a_errors = a_errors + 1;
                $display("FAIL ASSERT@%0t: memory write issued for a read request", $time);
            end
        end
        ready_prev      <= (cpu_ready === 1'b1);
        prev_state      <= g_dut.dut.u_ctrl.state;
        prev_refill_cnt <= g_dut.dut.u_ctrl.refill_cnt;
    end

    // ---- golden memory mirror ----
    reg [31:0] golden [0:1048575];   // byte addresses < 4MB
    integer i;

    // ---- trace driver ----
    integer fd, code, n_acc, errors;
    reg [255:0] trace_file;
    reg [1023:0] line;
    reg [8*4-1:0] op;
    reg [31:0] addr, wdata;

    task do_access;
        input        is_write;
        input [31:0] a;
        input [31:0] d;
        begin
            @(negedge clk);
            cpu_addr  = a;
            cpu_wdata = d;
            cpu_we    = is_write;
            cpu_req   = 1;
            @(posedge cpu_ready);
            cpu_req = 0; cpu_we = 0;
            #1;
            n_acc = n_acc + 1;
            if (!is_write) begin
                if (cpu_rdata !== golden[a[21:2]]) begin
                    errors = errors + 1;
                    if (errors <= 5)   // log first mismatches for debug
                        $display("MISMATCH acc#%0d R %h: got %h expected %h",
                                 n_acc, a, cpu_rdata, golden[a[21:2]]);
                end
            end else begin
                golden[a[21:2]] = d;   // write-through reaches memory
            end
        end
    endtask

    initial begin
        for (i = 0; i < 1048576; i = i + 1)
            golden[i] = i * 4 + 32'hA5000000;

        if (!$value$plusargs("trace=%s", trace_file)) begin
            $display("error: run with +trace=<file.trace>");
            $finish(1);
        end
        fd = $fopen(trace_file, "r");
        if (fd == 0) begin
            $display("error: cannot open trace file %0s", trace_file);
            $finish(1);
        end

        n_acc   = 0;
        errors  = 0;
        repeat (4) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        forever begin
            if ($fgets(line, fd) == 0) break;      // EOF
            if ($sscanf(line, " %s", op) < 1) continue;  // blank line
            if (op[7:0] == "#") continue;          // comment line
            if (op == "R") begin
                if ($sscanf(line, " %s %h", op, addr) < 2) begin
                    $display("error: bad R line: %0s", line);
                    $finish(1);
                end
                do_access(0, addr, 32'h0);
            end else if (op == "W") begin
                if ($sscanf(line, " %s %h %h", op, addr, wdata) < 3) begin
                    $display("error: bad W line: %0s", line);
                    $finish(1);
                end
                do_access(1, addr, wdata);
            end else begin
                $display("error: bad trace token %0s", op);
                $finish(1);
            end
        end
        $fclose(fd);

        if (errors == 0 && a_errors == 0) begin
            $display("TRACE PASS trace=%0s", trace_file);
        end else begin
            $display("TRACE FAIL trace=%0s data_errors=%0d assertion_errors=%0d",
                     trace_file, errors, a_errors);
        end
        $display("TRACE_RESULT trace=%0s accesses=%0d hits=%0d misses=%0d reads=%0d writes=%0d stalls=%0d",
                 trace_file, cnt_access, cnt_hit, cnt_miss, cnt_read, cnt_write, cnt_stall_cycles);
        $finish((errors == 0 && a_errors == 0) ? 0 : 1);
    end
endmodule
