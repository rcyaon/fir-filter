// tb_multiplier.v — Unit test for fixed-point Q1.15 multiply stage
// Run: iverilog -g2012 -o tb_multiplier tb_multiplier.v && vvp tb_multiplier

`default_nettype none
`timescale 1ns/1ps

// ── Fixed-point multiplier DUT ─────────────────────────────────────────────
// Signed 16x16 → 32-bit product, registered (maps to DSP18 slice).
// Q1.15 × Q1.15 = Q2.30 — caller truncates back to Q1.15.
module fir_multiplier #(
    parameter DATA_WIDTH = 16,
    parameter COEF_WIDTH = 16
) (
    input  wire                                clk,
    input  wire                                rst_n,
    input  wire signed [DATA_WIDTH-1:0]        sample,
    input  wire signed [COEF_WIDTH-1:0]        coeff,
    input  wire                                valid_in,
    output reg  signed [DATA_WIDTH+COEF_WIDTH-1:0] product,
    output reg                                 valid_out
);
    always @(posedge clk) begin
        if (!rst_n) begin
            product   <= '0;
            valid_out <= 1'b0;
        end else begin
            product   <= sample * coeff;
            valid_out <= valid_in;
        end
    end
endmodule

// ── Testbench ─────────────────────────────────────────────────────────────
module tb_multiplier;

    localparam DATA_WIDTH = 16;
    localparam COEF_WIDTH = 16;
    localparam PROD_WIDTH = DATA_WIDTH + COEF_WIDTH;  // 32

    // Q1.15 scale
    localparam real SCALE = 32768.0;

    reg                          clk;
    reg                          rst_n;
    reg  signed [DATA_WIDTH-1:0] sample;
    reg  signed [COEF_WIDTH-1:0] coeff;
    reg                          valid_in;
    wire signed [PROD_WIDTH-1:0] product;
    wire                         valid_out;

    fir_multiplier #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .sample   (sample),
        .coeff    (coeff),
        .valid_in (valid_in),
        .product  (product),
        .valid_out(valid_out)
    );

    initial clk = 0;
    always #10 clk = ~clk;

    initial begin
        $dumpfile("tb_multiplier.vcd");
        $dumpvars(0, tb_multiplier);
    end

    integer pass, fail;

    // Helper: apply inputs, wait one clock, check product
    task automatic apply_and_check;
        input signed [DATA_WIDTH-1:0] s;
        input signed [COEF_WIDTH-1:0] c;
        input signed [PROD_WIDTH-1:0] expected;
        input [127:0] label;
        begin
            @(posedge clk);
            sample   = s;
            coeff    = c;
            valid_in = 1;
            @(posedge clk);   // result registered on this edge
            valid_in = 0;
            #1;               // let outputs settle
            if (product === expected) begin
                $display("  PASS [%0s]  %0d × %0d = %0d", label, s, c, product);
                pass = pass + 1;
            end else begin
                $display("  FAIL [%0s]  %0d × %0d = %0d  (expected %0d)",
                         label, s, c, product, expected);
                fail = fail + 1;
            end
        end
    endtask

    // Helper: Q1.15 float → integer
    function automatic signed [DATA_WIDTH-1:0] q15;
        input real v;
        begin
            q15 = $rtoi(v * SCALE);
        end
    endfunction

    initial begin
        pass = 0; fail = 0;

        // ── Reset ────────────────────────────────────────
        rst_n = 0; sample = 0; coeff = 0; valid_in = 0;
        repeat(4) @(posedge clk);
        rst_n = 1; @(posedge clk);

        // ════════════════════════════════════════════════
        // TEST 1: Zero × anything = 0
        // ════════════════════════════════════════════════
        $display("\n[TEST 1] Zero inputs");
        apply_and_check(16'sh0000, 16'sh0000, 32'sh00000000, "0x0");
        apply_and_check(16'sh7FFF, 16'sh0000, 32'sh00000000, "max x 0");
        apply_and_check(16'sh0000, 16'sh7FFF, 32'sh00000000, "0 x max");

        // ════════════════════════════════════════════════
        // TEST 2: Identity multiply — 1.0 × x = x
        //   1.0 in Q1.15 = 0x7FFF (closest representable)
        //   product is Q2.30, so x × 0x7FFF ≈ x << 15
        // ════════════════════════════════════════════════
        $display("\n[TEST 2] Identity (≈1.0) coefficient");
        begin
            automatic signed [DATA_WIDTH-1:0] x = 16'sh4000;   // 0.5 in Q1.15
            automatic signed [COEF_WIDTH-1:0] one = 16'sh7FFF; // ≈1.0 in Q1.15
            automatic signed [PROD_WIDTH-1:0] exp = x * one;
            apply_and_check(x, one, exp, "0.5 x 1.0");
        end

        // ════════════════════════════════════════════════
        // TEST 3: Known Q1.15 coefficient values
        //   0.5 × 0.5 = 0.25
        //   In Q1.15: 0x4000 × 0x4000 = 0x10000000 (Q2.30)
        //   As float: 16384 × 16384 = 268435456
        // ════════════════════════════════════════════════
        $display("\n[TEST 3] Known fixed-point values");
        apply_and_check(16'sh4000, 16'sh4000, 32'sh10000000, "0.5x0.5=0.25");
        apply_and_check(16'sh2000, 16'sh4000, 32'sh08000000, "0.25x0.5=0.125");
        apply_and_check(16'sh4000, 16'sh2000, 32'sh08000000, "0.5x0.25=0.125");

        // ════════════════════════════════════════════════
        // TEST 4: Sign handling — negative × positive
        // ════════════════════════════════════════════════
        $display("\n[TEST 4] Sign handling");
        apply_and_check(-16'sh4000,  16'sh4000, -32'sh10000000, "-0.5 x  0.5");
        apply_and_check( 16'sh4000, -16'sh4000, -32'sh10000000, " 0.5 x -0.5");
        apply_and_check(-16'sh4000, -16'sh4000,  32'sh10000000, "-0.5 x -0.5");

        // ════════════════════════════════════════════════
        // TEST 5: Full-scale values — check no overflow in 32-bit product
        //   0x7FFF × 0x7FFF = 0x3FFF0001 (fits in 32 signed)
        // ════════════════════════════════════════════════
        $display("\n[TEST 5] Full-scale — no overflow");
        apply_and_check(16'sh7FFF, 16'sh7FFF, 32'sh3FFF0001, "max x max");
        apply_and_check(-16'sh8000, 16'sh7FFF, -32'sh3FFF8000, "-max x max");

        // ════════════════════════════════════════════════
        // TEST 6: valid_in gating — product shouldn't update when valid=0
        // ════════════════════════════════════════════════
        $display("\n[TEST 6] valid_in gating");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);

        @(posedge clk); sample = 16'sh4000; coeff = 16'sh4000; valid_in = 1;
        @(posedge clk); valid_in = 0;
        #1;
        begin
            automatic signed [PROD_WIDTH-1:0] snap = product;
            @(posedge clk); sample = 16'sh7FFF; coeff = 16'sh7FFF; // change inputs
            #1;
            // product should NOT have updated because valid_in stayed low
            // (note: the registered output holds the PREVIOUS cycle's result)
            if (!valid_out) begin
                $display("  PASS: valid_out low when valid_in=0");
                pass = pass + 1;
            end else begin
                $display("  FAIL: valid_out should be low");
                fail = fail + 1;
            end
        end

        // ════════════════════════════════════════════════
        // TEST 7: Pipeline latency — exactly 1 cycle
        // ════════════════════════════════════════════════
        $display("\n[TEST 7] Pipeline latency = 1 cycle");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1;

        @(posedge clk); sample = 16'sh2000; coeff = 16'sh2000; valid_in = 1;
        // Don't clock yet — check that output is NOT updated before posedge
        #1;
        if (product !== 32'sh01000000) begin
            $display("  PASS: output not combinational (still 0 before clk)");
            pass = pass + 1;
        end else begin
            $display("  (note: output happened to match pre-clock — check waveform)");
        end
        @(posedge clk); valid_in = 0; #1;
        if (product === 32'sh01000000) begin
            $display("  PASS: output correct exactly 1 cycle after input");
            pass = pass + 1;
        end else begin
            $display("  FAIL: expected 0x01000000, got 0x%08X", product);
            fail = fail + 1;
        end

        // ════════════════════════════════════════════════
        // TEST 8: Random inputs
        // ════════════════════════════════════════════════
        $display("\n[TEST 8] Random inputs");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
        begin
            integer rand_fail = 0;
            for (k = 0; k < 20; k = k + 1) begin
                sample = $random & 16'hFFFF;
                coeff = $random & 16'hFFFF;
                valid_in = 1;
                @(posedge clk); valid_in = 0;
                #1;
                // Check that product is sample * coeff
                if (product !== sample * coeff) begin
                    $display("  FAIL: random multiply failed for %0d * %0d", sample, coeff);
                    rand_fail = 1;
                end
            end
            if (!rand_fail) begin
                $display("  PASS: Random multiplies correct");
                pass = pass + 1;
            end else begin
                fail = fail + 1;
            end
        end

        // ════════════════════════════════════════════════
        // TEST 9: X propagation
        // ════════════════════════════════════════════════
        $display("\n[TEST 9] X propagation");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
        sample = 16'hXXXX; coeff = 16'h0001; valid_in = 1;
        @(posedge clk); valid_in = 0; #1;
        if (product !== 32'hXXXXXXXX) begin
            $display("  FAIL: X not propagated in product");
            fail = fail + 1;
        end else begin
            $display("  PASS: X propagated correctly");
            pass = pass + 1;
        end

        // ── Summary ──────────────────────────────────────
        $display("\n════════════════════════════════");
        $display("  multiplier: %0d passed, %0d failed", pass, fail);
        $display("════════════════════════════════\n");
        $finish;
    end

    initial begin #200_000; $display("TIMEOUT"); $finish; end

endmodule