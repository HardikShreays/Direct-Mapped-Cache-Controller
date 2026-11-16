`timescale 1ns/1ps

// Phase 1 directed read-path verification for cache_top.
module tb_cache_basic;
    localparam integer CPU_TIMEOUT_CYCLES = 200;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         cpu_req = 1'b0;
    reg         cpu_we = 1'b0;
    reg  [31:0] cpu_addr = 32'b0;
    reg  [31:0] cpu_wdata = 32'b0;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;

    wire        mem_req;
    wire        mem_we;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [31:0] mem_rdata;
    wire        mem_ready;
    wire [31:0] cnt_access, cnt_hit, cnt_miss;
    wire [31:0] cnt_read, cnt_write, cnt_stall_cycles;

    integer memory_reads = 0;
    reg [31:0] completed_read_addr [0:31];

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

    main_memory_model #(.MEM_LATENCY(10), .MEM_WORDS(4096)) memory (
        .clk(clk), .rst(rst), .mem_req(mem_req), .mem_we(mem_we),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    always #5 clk = ~clk;

    // Count completed memory reads: these are the observed refill handshakes.
    always @(posedge clk) begin
        if (!rst && mem_ready && !mem_we) begin
            if (memory_reads >= 32) begin
                $display("FAIL memory monitor: too many completed reads (%0d)", memory_reads + 1);
                $finish(1);
            end
            completed_read_addr[memory_reads] = mem_addr;
            memory_reads = memory_reads + 1;
        end
        if (!rst && mem_ready && mem_we) begin
            $display("FAIL memory monitor: unexpected write in Phase 1 read tests at address %h", mem_addr);
            $finish(1);
        end
    end

    task read_and_check;
        input [31:0] address;
        input [31:0] expected;
        input [8*32-1:0] test_name;
        integer waited;
        begin
            @(negedge clk);
            cpu_addr = address;
            cpu_we = 1'b0;
            cpu_req = 1'b1;
            waited = 0;
            while (!cpu_ready && waited < CPU_TIMEOUT_CYCLES) begin
                @(negedge clk);
                waited = waited + 1;
            end
            if (!cpu_ready) begin
                $display("FAIL %0s: addr=%h expected=%h actual=%h memory_reads=%0d timeout after %0d cycles",
                         test_name, address, expected, cpu_rdata,
                         memory_reads, CPU_TIMEOUT_CYCLES);
                $finish(1);
            end
            if (cpu_rdata !== expected) begin
                $display("FAIL %0s: addr=%h expected=%h actual=%h memory_reads=%0d",
                         test_name, address, expected, cpu_rdata, memory_reads);
                $finish(1);
            end
            cpu_req = 1'b0;
            @(negedge clk);
        end
    endtask

    task expect_read_address;
        input integer position;
        input [31:0] expected;
        input [8*32-1:0] test_name;
        begin
            if (completed_read_addr[position] !== expected) begin
                $display("FAIL %0s: refill[%0d] expected address=%h actual=%h total_memory_reads=%0d",
                         test_name, position, expected,
                         completed_read_addr[position], memory_reads);
                $finish(1);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/cache.vcd");
        $dumpvars(0, tb_cache_basic);
    end

    // Independent guard in case reset or a broken handshake prevents a task
    // timeout from advancing.
    initial begin
        #50000;
        $display("FAIL global watchdog: simulation exceeded 5000 clock cycles (memory_reads=%0d)",
                 memory_reads);
        $finish(1);
    end

    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        read_and_check(32'h00000000, 32'hA5000000, "A cold read miss");
        if (memory_reads !== 4) begin
            $display("FAIL A cold read miss: addr=%h expected=%h actual=%h expected_memory_reads=4 actual_memory_reads=%0d",
                     32'h00000000, 32'hA5000000, cpu_rdata, memory_reads);
            $finish(1);
        end
        expect_read_address(0, 32'h00000000, "A cold read miss");
        expect_read_address(1, 32'h00000004, "A cold read miss");
        expect_read_address(2, 32'h00000008, "A cold read miss");
        expect_read_address(3, 32'h0000000C, "A cold read miss");
        $display("PASS A: cold read miss refilled 00, 04, 08, 0C");

        read_and_check(32'h00000000, 32'hA5000000, "B hit after refill");
        if (memory_reads !== 4) begin
            $display("FAIL B hit after refill: addr=%h expected=%h actual=%h expected_memory_reads=4 actual_memory_reads=%0d",
                     32'h00000000, 32'hA5000000, cpu_rdata, memory_reads);
            $finish(1);
        end
        $display("PASS B: repeated read hit used no memory transaction");

        read_and_check(32'h00000004, 32'hA5000004, "C same-block offset 04");
        read_and_check(32'h00000008, 32'hA5000008, "C same-block offset 08");
        read_and_check(32'h0000000C, 32'hA500000C, "C same-block offset 0C");
        if (memory_reads !== 4) begin
            $display("FAIL C same-block offsets: addr=%h expected=%h actual=%h expected_memory_reads=4 actual_memory_reads=%0d",
                     cpu_addr, 32'hA500000C, cpu_rdata, memory_reads);
            $finish(1);
        end
        $display("PASS C: all three same-block offsets were hits");

        read_and_check(32'h00000400, 32'hA5000400, "D conflict miss at 00000400");
        if (memory_reads !== 8) begin
            $display("FAIL D conflict miss: addr=%h expected=%h actual=%h expected_memory_reads=8 actual_memory_reads=%0d",
                     32'h00000400, 32'hA5000400, cpu_rdata, memory_reads);
            $finish(1);
        end
        expect_read_address(4, 32'h00000400, "D conflict refill");
        expect_read_address(5, 32'h00000404, "D conflict refill");
        expect_read_address(6, 32'h00000408, "D conflict refill");
        expect_read_address(7, 32'h0000040C, "D conflict refill");

        read_and_check(32'h00000000, 32'hA5000000, "D evicted block misses again");
        if (memory_reads !== 12) begin
            $display("FAIL D evicted block: addr=%h expected=%h actual=%h expected_memory_reads=12 actual_memory_reads=%0d",
                     32'h00000000, 32'hA5000000, cpu_rdata, memory_reads);
            $finish(1);
        end
        expect_read_address(8,  32'h00000000, "D replacement refill");
        expect_read_address(9,  32'h00000004, "D replacement refill");
        expect_read_address(10, 32'h00000008, "D replacement refill");
        expect_read_address(11, 32'h0000000C, "D replacement refill");
        $display("PASS D: same-index conflict caused refill and eviction");

        $display("ALL TESTS PASSED");
        $finish(0);
    end
endmodule
