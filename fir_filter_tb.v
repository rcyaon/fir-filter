// fir_filter_tb.v — Testbench for fir_filter.v
// Run with: iverilog -o fir_tb fir_filter_tb.v fir_filter.v && vvp fir_tb
// View waveforms: gtkwave fir_filter_tb.vcd

`default_nettype none
`timescale 1ns/1ps

module fir_filter_tb;

    // ── DUT signals ───────────────────────────────────
    reg         clk;
    reg         rst_n;
    reg  signed [15:0] sample_in;
    reg         valid_in;
    wire signed [15:0] sample_out;
    wire        valid_out;

    // ── Instantiate DUT ───────────────────────────────
    fir_filter #(
        .TAPS       (16),
        .DATA_WIDTH (16),
        .COEF_WIDTH (16),
        .ACC_WIDTH  (36)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .sample_in  (sample_in),
        .valid_in   (valid_in),
        .sample_out (sample_out),
        .valid_out  (valid_out)
    );

    // ── Clock — 50 MHz (20 ns period) ─────────────────
    initial clk = 0;
    always #10 clk = ~clk;

    // ── VCD dump for GTKWave ──────────────────────────
    initial begin
        $dumpfile("fir_filter_tb.vcd");
        $dumpvars(0, fir_filter_tb);
    end

    // ── Test stimulus ─────────────────────────────────
    integer k;
    integer pass_count;
    integer fail_count;

    // Q1.15 scale factor
    localparam real SCALE = 32768.0;

    // Sine wave parameters
    // Passband: normalised freq 0.05 (well below 0.2 cutoff) → should pass
    // Stopband: normalised freq 0.40 (well above 0.2 cutoff) → should attenuate
    localparam integer N_SAMPLES   = 256;
    localparam real    PI          = 3.14159265358979;
    localparam real    FREQ_PASS   = 0.05;   // normalised (fraction of Nyquist)
    localparam real    FREQ_STOP   = 0.40;

    real    sine_pass  [0:N_SAMPLES-1];
    real    sine_stop  [0:N_SAMPLES-1];
    integer output_log [0:N_SAMPLES-1];
    integer output_idx;

    // ── Pre-compute sine tables ───────────────────────
    initial begin
        for (k = 0; k < N_SAMPLES; k = k + 1) begin
            sine_pass[k] = $sin(2.0 * PI * FREQ_PASS * k);
            sine_stop[k] = $sin(2.0 * PI * FREQ_STOP * k);
        end
    end

    // ── Capture outputs ───────────────────────────────
    initial output_idx = 0;
    always @(posedge clk) begin
        if (valid_out) begin
            output_log[output_idx] <= sample_out;
            output_idx <= output_idx + 1;
        end
    end

    // ── Main test sequence ────────────────────────────
    initial begin
        pass_count = 0;
        fail_count = 0;

        // ── Reset ─────────────────────────────────────
        rst_n     = 0;
        valid_in  = 0;
        sample_in = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // ════════════════════════════════════════════
        // TEST 1: Zero input → zero output
        // ════════════════════════════════════════════
        $display("\n[TEST 1] Zero input — expect zero output");
        repeat(30) begin
            @(posedge clk);
            sample_in = 16'sh0000;
            valid_in  = 1;
        end
        @(posedge clk); valid_in = 0;
        repeat(5) @(posedge clk);

        if (sample_out === 16'sh0000)
            $display("  PASS: output is zero");
        else begin
            $display("  FAIL: output = %0d (expected 0)", sample_out);
            fail_count = fail_count + 1;
        end

        // ════════════════════════════════════════════
        // TEST 2: Impulse response — check shape
        //   Feed a single +max impulse, then zeros.
        //   Outputs should match (scaled) filter coefficients.
        // ════════════════════════════════════════════
        $display("\n[TEST 2] Impulse response");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
        output_idx = 0;

        // Single impulse
        @(posedge clk);
        sample_in = 16'sh7FFF;   // Full-scale positive
        valid_in  = 1;
        @(posedge clk);
        sample_in = 16'sh0000;   // Drain with zeros

        repeat(TAPS + 10) @(posedge clk);
        valid_in = 0;
        repeat(5) @(posedge clk);

        $display("  Impulse response outputs (first %0d):", output_idx);
        for (k = 0; k < output_idx && k < 20; k = k + 1)
            $display("    y[%0d] = %0d  (0x%04X)", k, $signed(output_log[k]), output_log[k] & 16'hFFFF);

        // Basic sanity: response should be non-zero and then decay
        if (output_log[8] !== 0) begin
            $display("  PASS: impulse response is non-zero at peak");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: impulse response is zero at expected peak");
            fail_count = fail_count + 1;
        end

        // ════════════════════════════════════════════
        // TEST 3: DC input — output should equal input
        //   A FIR with unity DC gain: y → x after settling
        // ════════════════════════════════════════════
        $display("\n[TEST 3] DC input — expect output ≈ input after settling");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);

        repeat(TAPS * 3) begin
            @(posedge clk);
            sample_in = 16'sh4000;   // 0.5 in Q1.15
            valid_in  = 1;
        end
        @(posedge clk); valid_in = 0;
        repeat(5) @(posedge clk);

        // Allow ±128 LSB tolerance for quantisation
        if ($signed(sample_out) > (16'sh4000 - 128) &&
            $signed(sample_out) < (16'sh4000 + 128)) begin
            $display("  PASS: DC output = %0d (expected ~16384)", $signed(sample_out));
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: DC output = %0d (expected ~16384)", $signed(sample_out));
            fail_count = fail_count + 1;
        end

        // ════════════════════════════════════════════
        // TEST 4: Passband sine — check it passes through
        //   freq = 0.05 (well below cutoff 0.2)
        //   Output amplitude should be close to input amplitude
        // ════════════════════════════════════════════
        $display("\n[TEST 4] Passband sine (f=0.05) — expect minimal attenuation");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
        output_idx = 0;

        repeat(N_SAMPLES) begin : passband_loop
            integer idx;
            idx = output_idx;   // capture before clock edge
            @(posedge clk);
            sample_in = $rtoi(sine_pass[idx < N_SAMPLES ? idx : N_SAMPLES-1] * SCALE);
            valid_in  = 1;
        end
        @(posedge clk); valid_in = 0;
        repeat(TAPS + 5) @(posedge clk);

        begin : pb_check
            real max_out;
            integer j;
            max_out = 0;
            for (j = TAPS; j < output_idx; j = j + 1) begin
                real v;
                v = $signed(output_log[j]);
                if (v < 0) v = -v;
                if (v > max_out) max_out = v;
            end
            $display("  Peak output amplitude = %0.1f (expected ~%0.1f)", max_out, SCALE * 0.85);
            if (max_out > SCALE * 0.7) begin
                $display("  PASS: passband signal not significantly attenuated");
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: passband signal too attenuated (%.1f%%)", max_out / SCALE * 100);
                fail_count = fail_count + 1;
            end
        end

        // ════════════════════════════════════════════
        // TEST 5: Stopband sine — check attenuation
        //   freq = 0.40 (well above cutoff 0.2)
        //   Output amplitude should be much smaller than input
        // ════════════════════════════════════════════
        $display("\n[TEST 5] Stopband sine (f=0.40) — expect strong attenuation");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
        output_idx = 0;

        repeat(N_SAMPLES) begin : stopband_loop
            integer idx;
            idx = output_idx;
            @(posedge clk);
            sample_in = $rtoi(sine_stop[idx < N_SAMPLES ? idx : N_SAMPLES-1] * SCALE);
            valid_in  = 1;
        end
        @(posedge clk); valid_in = 0;
        repeat(TAPS + 5) @(posedge clk);

        begin : sb_check
            real max_out;
            integer j;
            max_out = 0;
            for (j = TAPS; j < output_idx; j = j + 1) begin
                real v;
                v = $signed(output_log[j]);
                if (v < 0) v = -v;
                if (v > max_out) max_out = v;
            end
            $display("  Peak output amplitude = %0.1f (expected < %0.1f)", max_out, SCALE * 0.10);
            if (max_out < SCALE * 0.10) begin
                $display("  PASS: stopband signal sufficiently attenuated (%.1f%%)", max_out / SCALE * 100);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: stopband not attenuated enough (%.1f%%)", max_out / SCALE * 100);
                fail_count = fail_count + 1;
            end
        end

        // ════════════════════════════════════════════
        // TEST 6: valid_in gating — output only when valid
        // ════════════════════════════════════════════
        $display("\n[TEST 6] valid_in gating — stalled input should stall output");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);

        // Send one sample
        @(posedge clk); sample_in = 16'sh1000; valid_in = 1;
        @(posedge clk); valid_in = 0;
        // Hold for many cycles — valid_out should not fire yet
        repeat(5) @(posedge clk);
        if (!valid_out) begin
            $display("  PASS: valid_out stays low when valid_in is gated");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: valid_out asserted unexpectedly");
            fail_count = fail_count + 1;
        end

        // ── Summary ───────────────────────────────────
        $display("\n════════════════════════════════");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("════════════════════════════════\n");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED — check waveform in fir_filter_tb.vcd");

        $finish;
    end

    // ── Timeout watchdog ──────────────────────────────
    initial begin
        #2_000_000;
        $display("TIMEOUT: simulation exceeded 2ms — hung?");
        $finish;
    end

endmodule