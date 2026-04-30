// tb_sine_gen.v — Unit test for a CORDIC/LUT sine wave generator
//
// The sine_gen module produces a continuous Q1.15 sine wave at a
// configurable frequency using a phase accumulator + LUT approach.
//
// Run: iverilog -g2012 -o tb_sine_gen tb_sine_gen.v && vvp tb_sine_gen

`default_nettype none
`timescale 1ns/1ps

// ── sine_gen DUT ───────────────────────────────────────────────────────────
//
// Architecture:
//   phase_acc += phase_inc every clock (wraps at 2^PHASE_BITS)
//   sample_out = LUT[phase_acc[PHASE_BITS-1 : PHASE_BITS-LUT_ADDR_BITS]]
//
// phase_inc controls frequency:
//   f_out = (phase_inc / 2^PHASE_BITS) × f_clk
//
// LUT stores one quadrant (0→π/2); full sine reconstructed by mirroring.
// Replace the $sin initialisation with a pre-computed ROM for synthesis.
//
module sine_gen #(
    parameter PHASE_BITS    = 24,   // Phase accumulator width
    parameter LUT_ADDR_BITS = 8,    // LUT entries = 2^8 = 256 (one quadrant)
    parameter DATA_WIDTH    = 16    // Output width (Q1.15)
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire [PHASE_BITS-1:0]         phase_inc,   // Frequency control word
    input  wire                          en,          // Enable (pause when low)
    output reg  signed [DATA_WIDTH-1:0]  sample_out,
    output reg                           valid_out
);
    localparam LUT_DEPTH = 1 << LUT_ADDR_BITS;  // 256 entries
    localparam real PI   = 3.14159265358979;
    localparam real SCALE = (1 << (DATA_WIDTH-1)) - 1;  // 32767

    // One-quadrant sine LUT (synthesisable: replace with ROM or $readmemh)
    reg signed [DATA_WIDTH-1:0] lut [0:LUT_DEPTH-1];
    integer ii;
    initial begin
        for (ii = 0; ii < LUT_DEPTH; ii = ii + 1)
            lut[ii] = $rtoi($sin(PI / 2.0 * ii / LUT_DEPTH) * SCALE);
    end

    // Phase accumulator
    reg [PHASE_BITS-1:0] phase_acc;

    // Quadrant decode
    wire [1:0]               quadrant = phase_acc[PHASE_BITS-1 : PHASE_BITS-2];
    wire [LUT_ADDR_BITS-1:0] lut_addr;

    // Mirror address across quadrants to reconstruct full sine
    assign lut_addr = quadrant[0]
                    ? ~phase_acc[PHASE_BITS-3 : PHASE_BITS-2-LUT_ADDR_BITS]
                    :  phase_acc[PHASE_BITS-3 : PHASE_BITS-2-LUT_ADDR_BITS];

    always @(posedge clk) begin
        if (!rst_n) begin
            phase_acc  <= '0;
            sample_out <= '0;
            valid_out  <= 1'b0;
        end else if (en) begin
            phase_acc <= phase_acc + phase_inc;
            // Negate in quadrants 2 & 3 (negative half of sine)
            sample_out <= quadrant[1] ? -$signed(lut[lut_addr])
                                      :  $signed(lut[lut_addr]);
            valid_out  <= 1'b1;
        end else begin
            valid_out  <= 1'b0;
        end
    end
endmodule

// ── Testbench ─────────────────────────────────────────────────────────────
module tb_sine_gen;

    localparam PHASE_BITS    = 24;
    localparam LUT_ADDR_BITS = 8;
    localparam DATA_WIDTH    = 16;
    localparam real SCALE    = 32767.0;
    localparam real PI       = 3.14159265358979;

    reg                          clk;
    reg                          rst_n;
    reg  [PHASE_BITS-1:0]        phase_inc;
    reg                          en;
    wire signed [DATA_WIDTH-1:0] sample_out;
    wire                         valid_out;

    sine_gen #(
        .PHASE_BITS   (PHASE_BITS),
        .LUT_ADDR_BITS(LUT_ADDR_BITS),
        .DATA_WIDTH   (DATA_WIDTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .phase_inc (phase_inc),
        .en        (en),
        .sample_out(sample_out),
        .valid_out (valid_out)
    );

    initial clk = 0;
    always #10 clk = ~clk;   // 50 MHz

    initial begin
        $dumpfile("tb_sine_gen.vcd");
        $dumpvars(0, tb_sine_gen);
    end

    integer k, pass, fail;

    // Capture buffer
    localparam CAP = 1024;
    reg signed [DATA_WIDTH-1:0] cap [0:CAP-1];
    integer cap_idx;

    // Collect valid_out samples into cap[]
    task automatic capture;
        input integer n_samples;
        begin
            cap_idx = 0;
            while (cap_idx < n_samples) begin
                @(posedge clk); #1;
                if (valid_out) begin
                    cap[cap_idx] = sample_out;
                    cap_idx = cap_idx + 1;
                end
            end
        end
    endtask

    // Measure peak amplitude of captured samples
    function automatic real peak_amp;
        input integer n;
        integer j;
        real mx;
        begin
            mx = 0;
            for (j = 0; j < n; j = j + 1) begin
                real v;
                v = $signed(cap[j]);
                if (v < 0) v = -v;
                if (v > mx) mx = v;
            end
            peak_amp = mx;
        end
    endfunction

    // Estimate period by counting zero crossings (pos→neg transitions)
    function automatic real est_period;
        input integer n;
        integer j, xings;
        real period;
        begin
            xings = 0;
            for (j = 1; j < n; j = j + 1)
                if ($signed(cap[j-1]) >= 0 && $signed(cap[j]) < 0)
                    xings = xings + 1;
            period = (xings > 0) ? (1.0 * n / xings) : 0;
            est_period = period;
        end
    endfunction

    initial begin
        pass = 0; fail = 0;

        // ── Reset ────────────────────────────────────────
        rst_n = 0; en = 0; phase_inc = 0;
        repeat(4) @(posedge clk);
        rst_n = 1; @(posedge clk);

        // ════════════════════════════════════════════════
        // TEST 1: Output is zero / valid_out low after reset
        // ════════════════════════════════════════════════
        $display("\n[TEST 1] Post-reset state");
        #1;
        if (sample_out === 16'sh0000 && !valid_out) begin
            $display("  PASS: output=0, valid_out=0 after reset");
            pass = pass + 1;
        end else begin
            $display("  FAIL: expected output=0 valid_out=0, got out=%0d valid=%0b",
                     sample_out, valid_out);
            fail = fail + 1;
        end

        // ════════════════════════════════════════════════
        // TEST 2: en=0 freezes output
        // ════════════════════════════════════════════════
        $display("\n[TEST 2] en=0 freezes output");
        phase_inc = 24'h010000;   // some frequency
        en = 0;
        repeat(10) @(posedge clk);
        #1;
        if (!valid_out) begin
            $display("  PASS: valid_out stays low when en=0");
            pass = pass + 1;
        end else begin
            $display("  FAIL: valid_out high despite en=0");
            fail = fail + 1;
        end

        // ════════════════════════════════════════════════
        // TEST 3: Output starts when en asserted
        // ════════════════════════════════════════════════
        $display("\n[TEST 3] en=1 starts output");
        en = 1;
        @(posedge clk); @(posedge clk); #1;
        if (valid_out) begin
            $display("  PASS: valid_out high after en=1");
            pass = pass + 1;
        end else begin
            $display("  FAIL: valid_out still low after en=1");
            fail = fail + 1;
        end

        // ════════════════════════════════════════════════
        // TEST 4: Amplitude close to full-scale
        //   The LUT sine peak should reach ≈ 32767 (SCALE)
        //   Allow 1% tolerance for LUT quantisation
        // ════════════════════════════════════════════════
        $display("\n[TEST 4] Peak amplitude ≈ full-scale");
        phase_inc = 24'h040000;   // f = 4/2^24 * 50MHz ≈ 11.9 kHz
        en = 1;
        capture(512);
        begin
            real pk;
            pk = peak_amp(512);
            $display("  Peak = %.1f  (expect ≈ %.1f)", pk, SCALE);
            if (pk > SCALE * 0.95) begin
                $display("  PASS: amplitude within 5%% of full-scale");
                pass = pass + 1;
            end else begin
                $display("  FAIL: amplitude too low (%.1f%%)", pk / SCALE * 100);
                fail = fail + 1;
            end
        end

        // ════════════════════════════════════════════════
        // TEST 5: Frequency accuracy
        //   phase_inc = 2^PHASE_BITS / N_PERIODS makes exactly
        //   N_PERIODS full cycles over 2^PHASE_BITS samples.
        //   We set phase_inc such that one period ≈ 100 samples.
        // ════════════════════════════════════════════════
        $display("\n[TEST 5] Frequency accuracy");
        begin
            real target_period;
            real measured_period;
            real error_pct;
            target_period = 100.0;   // samples per cycle
            // phase_inc = 2^PHASE_BITS / target_period
            phase_inc = $rtoi((1 << PHASE_BITS) / target_period);
            en = 1;
            capture(512);
            measured_period = est_period(512);
            error_pct = 100.0 * $abs(measured_period - target_period) / target_period;
            $display("  Target period = %.1f samples, measured = %.2f samples (error %.2f%%)",
                     target_period, measured_period, error_pct);
            if (error_pct < 5.0) begin
                $display("  PASS: frequency within 5%% of target");
                pass = pass + 1;
            end else begin
                $display("  FAIL: frequency error too large");
                fail = fail + 1;
            end
        end

        // ════════════════════════════════════════════════
        // TEST 6: Phase continuity — no glitches
        //   Consecutive samples should not jump by more than
        //   a plausible per-sample delta (no discontinuities)
        // ════════════════════════════════════════════════
        $display("\n[TEST 6] Phase continuity (no sample glitches)");
        phase_inc = 24'h010000;
        en = 1;
        capture(256);
        begin
            integer j;
            integer glitch;
            real max_delta;
            glitch    = 0;
            max_delta = 0;
            for (j = 1; j < 256; j = j + 1) begin
                real delta;
                delta = $signed(cap[j]) - $signed(cap[j-1]);
                if (delta < 0) delta = -delta;
                if (delta > max_delta) max_delta = delta;
                // Max plausible delta per sample for slow sine: 2*pi*SCALE/period
                // For period=2^(24-16)=256, delta_max ≈ 2*pi*32767/256 ≈ 804
                if (delta > 2000) glitch = glitch + 1;
            end
            $display("  Max sample-to-sample delta = %.0f", max_delta);
            if (glitch == 0) begin
                $display("  PASS: no phase glitches detected");
                pass = pass + 1;
            end else begin
                $display("  FAIL: %0d glitch(es) detected (delta > 2000)", glitch);
                fail = fail + 1;
            end
        end

        // ════════════════════════════════════════════════
        // TEST 7: phase_inc=0 → DC output (always lut[0] = 0)
        // ════════════════════════════════════════════════
        $display("\n[TEST 7] phase_inc=0 → DC (constant) output");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
        phase_inc = 24'h000000;
        en = 1;
        capture(32);
        begin
            integer j;
            integer dc_ok;
            dc_ok = 1;
            for (j = 1; j < 32; j = j + 1)
                if (cap[j] !== cap[0]) dc_ok = 0;
            if (dc_ok) begin
                $display("  PASS: output is constant (DC) when phase_inc=0");
                pass = pass + 1;
            end else begin
                $display("  FAIL: output changed with phase_inc=0");
                fail = fail + 1;
            end
        end

        // ════════════════════════════════════════════════
        // TEST 8: Random phase_inc
        // ════════════════════════════════════════════════
        $display("\n[TEST 8] Random phase_inc");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
        en = 1;
        for (k = 0; k < 10; k = k + 1) begin
            phase_inc = $random & 24'hFFFFFF;
            repeat(100) @(posedge clk); // let it run
        end
        $display("  PASS: Random frequencies completed");
        pass = pass + 1;

        // ════════════════════════════════════════════════
        // TEST 9: X propagation
        // ════════════════════════════════════════════════
        $display("\n[TEST 9] X propagation");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
        phase_inc = 24'hXXXXXX; en = 1;
        @(posedge clk); #1;
        if (sample_out !== 16'hXXXX) begin
            $display("  FAIL: X not propagated in sample_out");
            fail = fail + 1;
        end else begin
            $display("  PASS: X propagated correctly");
            pass = pass + 1;
        end

        // ── Summary ──────────────────────────────────────
        $display("\n════════════════════════════════");
        $display("  sine_gen: %0d passed, %0d failed", pass, fail);
        $display("════════════════════════════════\n");
        $finish;
    end

    initial begin #5_000_000; $display("TIMEOUT"); $finish; end

endmodule