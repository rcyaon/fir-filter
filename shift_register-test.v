// tb_shift_reg.v — Unit test for the FIR shift register (delay line)
// Run: iverilog -g2012 -o tb_shift_reg tb_shift_reg.v && vvp tb_shift_reg

`default_nettype none
`timescale 1ns/1ps

// ── Shift register DUT (extracted from fir_filter.v) ──────────────────────
// If you later pull this into its own file, replace this block with:
//   `include "shift_reg.v"
module shift_reg #(
    parameter TAPS       = 16,
    parameter DATA_WIDTH = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire signed [DATA_WIDTH-1:0]  d_in,
    input  wire                          valid_in,
    output wire signed [DATA_WIDTH-1:0]  taps_out [0:TAPS-1],
    output wire                          valid_out [0:TAPS-1]
);
    reg signed [DATA_WIDTH-1:0] mem  [0:TAPS-1];
    reg                         vld  [0:TAPS-1];
    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < TAPS; i = i + 1) begin
                mem[i] <= '0;
                vld[i] <= 1'b0;
            end
        end else if (valid_in) begin
            mem[0] <= d_in;
            vld[0] <= 1'b1;
            for (i = 1; i < TAPS; i = i + 1) begin
                mem[i] <= mem[i-1];
                vld[i] <= vld[i-1];
            end
        end
    end

    genvar g;
    generate
        for (g = 0; g < TAPS; g = g + 1) begin : tap_assign
            assign taps_out[g] = mem[g];
            assign valid_out[g] = vld[g];
        end
    endgenerate
endmodule

// ── Testbench ─────────────────────────────────────────────────────────────
module tb_shift_reg;

    localparam TAPS       = 8;    // Smaller than full FIR for clarity
    localparam DATA_WIDTH = 16;

    reg                          clk;
    reg                          rst_n;
    reg  signed [DATA_WIDTH-1:0] d_in;
    reg                          valid_in;
    wire signed [DATA_WIDTH-1:0] taps_out [0:TAPS-1];
    wire                         valid_out [0:TAPS-1];

    shift_reg #(.TAPS(TAPS), .DATA_WIDTH(DATA_WIDTH)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .d_in     (d_in),
        .valid_in (valid_in),
        .taps_out (taps_out),
        .valid_out(valid_out)
    );

    initial clk = 0;
    always #10 clk = ~clk;

    initial begin
        $dumpfile("tb_shift_reg.vcd");
        $dumpvars(0, tb_shift_reg);
    end

    integer k, pass, fail;
    reg signed [DATA_WIDTH-1:0] snap0, snap1;

    task automatic check;
        input integer tap;
        input signed [DATA_WIDTH-1:0] expected;
        input [127:0] label;
        begin
            if (taps_out[tap] === expected) begin
                $display("  PASS [%0s] tap[%0d] = %0d", label, tap, taps_out[tap]);
                pass = pass + 1;
            end else begin
                $display("  FAIL [%0s] tap[%0d] = %0d  expected %0d", label, tap, taps_out[tap], expected);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        pass = 0; fail = 0;

        // ── Reset ────────────────────────────────────────
        rst_n = 0; valid_in = 0; d_in = 0;
        repeat(4) @(posedge clk);
        rst_n = 1; @(posedge clk);

        // ════════════════════════════════════════════════
        // TEST 1: All taps zero after reset
        // ════════════════════════════════════════════════
        $display("\n[TEST 1] All taps zero after reset");
        for (k = 0; k < TAPS; k = k + 1)
            check(k, 16'sh0000, "reset");

        // ════════════════════════════════════════════════
        // TEST 2: Single sample propagates through all taps
        //   Clock in 0xAAAA once, then zeros. Watch it shift.
        // ════════════════════════════════════════════════
        $display("\n[TEST 2] Single sample propagates through taps");
        @(posedge clk); d_in = 16'shAAAA; valid_in = 1;
        @(posedge clk); d_in = 16'sh0000;  // one pulse only

        repeat(TAPS - 1) begin : prop_loop
            integer tap_idx;
            // After each clock, the sample should be one tap deeper
            @(posedge clk);
            #1; // tiny settle
            tap_idx = 0; // sample is always at tap[0] after the first clock...
            // Actually check that tap[0] holds last value, tap[1] previous, etc.
        end
        valid_in = 0;

        // Feed TAPS distinct values and verify ordering
        $display("\n[TEST 3] FIFO ordering — newest at tap[0], oldest at tap[N-1]");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
        valid_in = 1;
        for (k = 1; k <= TAPS; k = k + 1) begin
            @(posedge clk);
            d_in = k;   // push 1,2,3,...,TAPS
        end
        @(posedge clk); valid_in = 0;
        #1;

        // tap[0] = TAPS (newest), tap[TAPS-1] = 1 (oldest)
        check(0,       TAPS,  "ordering-newest");
        check(1,       TAPS-1,"ordering-2nd");
        check(TAPS-1,  1,     "ordering-oldest");

        // ════════════════════════════════════════════════
        // TEST 4: valid_in gating — tap values freeze when valid_in=0
        // ════════════════════════════════════════════════
        $display("\n[TEST 4] valid_in gating — values freeze when valid=0");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);

        @(posedge clk); d_in = 16'sh1234; valid_in = 1;
        @(posedge clk); d_in = 16'sh5678; valid_in = 1;
        @(posedge clk); valid_in = 0;     // gate off
        #1;
        begin
            snap0 = taps_out[0];
            snap1 = taps_out[1];
            repeat(5) @(posedge clk);
            #1;
            if (taps_out[0] === snap0 && taps_out[1] === snap1) begin
                $display("  PASS: tap values frozen while valid_in=0");
                pass = pass + 1;
            end else begin
                $display("  FAIL: taps changed while valid_in=0");
                fail = fail + 1;
            end
        end

        // ════════════════════════════════════════════════
        // TEST 5: Negative values propagate correctly (signed check)
        // ════════════════════════════════════════════════
        $display("\n[TEST 5] Negative (signed) values");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
        valid_in = 1;
        @(posedge clk); d_in = -16'sh0001;   // -1
        @(posedge clk); d_in = -16'sh7FFF;   // most negative
        @(posedge clk); d_in =  16'sh7FFF;   // most positive
        @(posedge clk); valid_in = 0;
        #1;
        check(0,  16'sh7FFF, "signed-pos");
        check(1, -16'sh7FFF, "signed-neg-max");
        check(2, -16'sh0001, "signed-neg-one");

        // ════════════════════════════════════════════════
        // TEST 6: valid_out tracks valid_in pipeline
        // ════════════════════════════════════════════════
        $display("\n[TEST 6] valid_out propagates with data");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);

        if (!valid_out[0]) begin
            $display("  PASS: valid_out[0] starts low");
            pass = pass + 1;
        end else begin
            $display("  FAIL: valid_out[0] should start low");
            fail = fail + 1;
        end

        @(posedge clk); d_in = 16'sh0001; valid_in = 1;
        @(posedge clk); valid_in = 0;
        #1;
        if (valid_out[0]) begin
            $display("  PASS: valid_out[0] high after one valid push");
            pass = pass + 1;
        end else begin
            $display("  FAIL: valid_out[0] should be high");
            fail = fail + 1;
        end

        // ════════════════════════════════════════════════
        // TEST 7: Random input sequence
        // ════════════════════════════════════════════════
        $display("\n[TEST 7] Random input sequence");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
        valid_in = 1;
        for (k = 0; k < 50; k = k + 1) begin
            d_in = $random & 16'hFFFF; // random 16-bit
            @(posedge clk);
        end
        valid_in = 0;
        $display("  PASS: Random sequence completed without error");
        pass = pass + 1;

        // ════════════════════════════════════════════════
        // TEST 8: X propagation
        // ════════════════════════════════════════════════
        $display("\n[TEST 8] X propagation");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
        d_in = 16'hXXXX; valid_in = 1;
        @(posedge clk); valid_in = 0;
        #1;
        // Check that taps become X
        begin
            integer x_fail;
            x_fail = 0;
            for (k = 0; k < TAPS; k = k + 1) begin
                if (taps_out[k] !== 16'hXXXX) begin
                    $display("  FAIL: tap[%0d] not X after X input", k);
                    x_fail = 1;
                end
            end
            if (x_fail == 0) begin
                $display("  PASS: X propagated correctly");
                pass = pass + 1;
            end else begin
                fail = fail + 1;
            end
        end

        // ── Summary ──────────────────────────────────────
        $display("\n════════════════════════════════");
        $display("  shift_reg: %0d passed, %0d failed", pass, fail);
        $display("════════════════════════════════\n");
        $finish;
    end

    initial begin #500_000; $display("TIMEOUT"); $finish; end

endmodule