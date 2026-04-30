// tb_uart_tx.v — Unit test for a simple UART transmitter
//
// uart_tx sends 8-N-1 frames (8 data bits, no parity, 1 stop bit).
// Baud rate = clk_freq / CLKS_PER_BIT.
//
// Run: iverilog -g2012 -o tb_uart_tx tb_uart_tx.v && vvp tb_uart_tx

`default_nettype none
`timescale 1ns/1ps

// ── uart_tx DUT ────────────────────────────────────────────────────────────
module uart_tx #(
    parameter CLKS_PER_BIT = 434   // 50 MHz / 115200 baud ≈ 434
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data_in,     // Byte to transmit
    input  wire       send,        // Pulse high for 1 cycle to start TX
    output reg        tx,          // Serial output line
    output reg        busy         // High while transmitting
);
    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;    // Baud clock divider counter
    reg [2:0]  bit_idx;    // Current data bit (0–7)
    reg [7:0]  shift_reg;  // Data shift register

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            tx       <= 1'b1;    // Idle = mark (high)
            busy     <= 1'b0;
            clk_cnt  <= '0;
            bit_idx  <= '0;
            shift_reg<= '0;
        end else begin
            case (state)

                S_IDLE: begin
                    tx  <= 1'b1;
                    busy<= 1'b0;
                    if (send) begin
                        shift_reg <= data_in;
                        clk_cnt   <= '0;
                        busy      <= 1'b1;
                        state     <= S_START;
                    end
                end

                S_START: begin
                    tx <= 1'b0;   // Start bit = space (low)
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= '0;
                        bit_idx <= '0;
                        state   <= S_DATA;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end

                S_DATA: begin
                    tx <= shift_reg[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= '0;
                        if (bit_idx == 7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else
                        clk_cnt <= clk_cnt + 1;
                end

                S_STOP: begin
                    tx <= 1'b1;   // Stop bit = mark (high)
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= '0;
                        busy    <= 1'b0;
                        state   <= S_IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end

            endcase
        end
    end
endmodule

// ── Testbench ─────────────────────────────────────────────────────────────
module tb_uart_tx;

    localparam CLKS_PER_BIT = 20;   // Shortened for fast simulation
                                     // (real: 434 for 50 MHz / 115200)

    reg        clk;
    reg        rst_n;
    reg  [7:0] data_in;
    reg        send;
    wire       tx;
    wire       busy;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .data_in (data_in),
        .send    (send),
        .tx      (tx),
        .busy    (busy)
    );

    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz (with CLKS_PER_BIT=20 → 5 MHz "baud")

    initial begin
        $dumpfile("tb_uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
    end

    integer pass, fail;

    // ── UART frame decoder ─────────────────────────────
    // Samples the tx line at the centre of each bit period.
    // Returns the decoded byte; sets frame_ok=0 on framing error.
    task automatic decode_frame;
        output [7:0] decoded;
        output integer frame_ok;
        integer i;
        begin
            frame_ok = 1;
            decoded  = 8'h00;

            // Wait for start bit (falling edge on tx)
            @(negedge tx);

            // Sample start bit at centre
            repeat(CLKS_PER_BIT / 2) @(posedge clk);
            if (tx !== 1'b0) begin
                $display("    decode_frame: start bit not low (got %b)", tx);
                frame_ok = 0;
            end

            // Sample 8 data bits
            for (i = 0; i < 8; i = i + 1) begin
                repeat(CLKS_PER_BIT) @(posedge clk);
                decoded[i] = tx;
            end

            // Sample stop bit
            repeat(CLKS_PER_BIT) @(posedge clk);
            if (tx !== 1'b1) begin
                $display("    decode_frame: stop bit not high (got %b)", tx);
                frame_ok = 0;
            end
        end
    endtask

    // ── Helper: transmit one byte and verify ───────────
    task automatic send_and_check;
        input [7:0] byte_val;
        input [127:0] label;
        reg [7:0] decoded;
        integer   frame_ok;
        begin
            // Wait until not busy
            @(posedge clk);
            while (busy) @(posedge clk);

            // Trigger transmission
            data_in = byte_val;
            send    = 1'b1;
            @(posedge clk);
            send = 1'b0;

            // Decode frame in parallel
            decode_frame(decoded, frame_ok);

            if (frame_ok && decoded === byte_val) begin
                $display("  PASS [%0s] TX 0x%02X → decoded 0x%02X", label, byte_val, decoded);
                pass = pass + 1;
            end else if (!frame_ok) begin
                $display("  FAIL [%0s] Framing error transmitting 0x%02X", label, byte_val);
                fail = fail + 1;
            end else begin
                $display("  FAIL [%0s] TX 0x%02X → decoded 0x%02X (mismatch)", label, byte_val, decoded);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        pass = 0; fail = 0;

        // ── Reset ────────────────────────────────────────
        rst_n = 0; send = 0; data_in = 8'h00;
        repeat(4) @(posedge clk);
        rst_n = 1; @(posedge clk);

        // ════════════════════════════════════════════════
        // TEST 1: Idle line is high (mark)
        // ════════════════════════════════════════════════
        $display("\n[TEST 1] Idle line is high (mark)");
        #1;
        if (tx === 1'b1 && !busy) begin
            $display("  PASS: tx=1, busy=0 at idle");
            pass = pass + 1;
        end else begin
            $display("  FAIL: tx=%b busy=%b (expected tx=1, busy=0)", tx, busy);
            fail = fail + 1;
        end

        // ════════════════════════════════════════════════
        // TEST 2: Transmit known bytes — check bit-level decode
        // ════════════════════════════════════════════════
        $display("\n[TEST 2] Transmit and decode known bytes");
        send_and_check(8'h55, "0x55 alternating");   // 0101_0101
        send_and_check(8'hAA, "0xAA alternating");   // 1010_1010
        send_and_check(8'h00, "0x00 all-zeros");
        send_and_check(8'hFF, "0xFF all-ones");
        send_and_check(8'hA5, "0xA5 mixed");

        // ════════════════════════════════════════════════
        // TEST 3: busy goes high on send, low after stop bit
        // ════════════════════════════════════════════════
        $display("\n[TEST 3] busy signal timing");
        @(posedge clk); while (busy) @(posedge clk);

        data_in = 8'h42; send = 1;
        @(posedge clk); send = 0;
        #1;
        if (busy) begin
            $display("  PASS: busy asserted immediately");
            pass = pass + 1;
        end else begin
            $display("  FAIL: busy not asserted after send");
            fail = fail + 1;
        end

        // Wait for end of transmission
        @(negedge busy);
        #1;
        if (!busy && tx === 1'b1) begin
            $display("  PASS: busy deasserted, tx returns to idle (high)");
            pass = pass + 1;
        end else begin
            $display("  FAIL: after tx done: busy=%b tx=%b", busy, tx);
            fail = fail + 1;
        end

        // ════════════════════════════════════════════════
        // TEST 4: send ignored while busy
        // ════════════════════════════════════════════════
        $display("\n[TEST 4] send ignored while busy");
        @(posedge clk); while (busy) @(posedge clk);

        data_in = 8'hDE; send = 1; @(posedge clk); send = 0;
        // Immediately try to send another byte mid-frame
        @(posedge clk);
        data_in = 8'hAD; send = 1; @(posedge clk); send = 0;

        // Decode — should get 0xDE, not 0xAD
        begin
            reg [7:0] decoded;
            integer   frame_ok;
            decode_frame(decoded, frame_ok);
            if (frame_ok && decoded === 8'hDE) begin
                $display("  PASS: first byte 0xDE transmitted correctly despite collision");
                pass = pass + 1;
            end else begin
                $display("  FAIL: got 0x%02X expected 0xDE (collision corrupted frame)", decoded);
                fail = fail + 1;
            end
        end

        // ════════════════════════════════════════════════
        // TEST 5: Back-to-back bytes — gap = 0 extra clocks
        // ════════════════════════════════════════════════
        $display("\n[TEST 5] Back-to-back byte transmission");
        @(posedge clk); while (busy) @(posedge clk);
        send_and_check(8'h31, "b2b-byte1");
        send_and_check(8'h32, "b2b-byte2");
        send_and_check(8'h33, "b2b-byte3");

        // ════════════════════════════════════════════════
        // TEST 6: ASCII 'U' (0x55) — classic UART baud check byte
        //   Pattern: 0101 0101 produces uniform bit periods, used
        //   by scopes/analysers to verify baud rate accuracy.
        // ════════════════════════════════════════════════
        $display("\n[TEST 6] ASCII 'U' (0x55) baud-rate check pattern");
        begin
            reg [7:0] decoded;
            integer   frame_ok;
            integer   start_time, end_time, measured_bits, expected_bits;

            @(posedge clk); while (busy) @(posedge clk);
            data_in = 8'h55; send = 1; @(posedge clk); send = 0;

            @(negedge tx);                     // falling edge = start bit
            start_time = $time;
            @(posedge busy == 0);              // wait for frame done
            end_time   = $time;

            // Total frame = 10 bit periods (1 start + 8 data + 1 stop)
            measured_bits = (end_time - start_time) / (CLKS_PER_BIT * 10);  // in clk units
            $display("  Frame duration = %0t ns  (expected %0d clk × 10 bits = %0d ns)",
                     end_time - start_time,
                     CLKS_PER_BIT,
                     CLKS_PER_BIT * 10 * 10);  // ×10 because 10ns per clk

            // Check timing within 5%
            begin
                real expected_ns, error_pct;
                expected_ns = CLKS_PER_BIT * 10 * 10.0;   // 10 ns per clk
                error_pct   = 100.0 * $abs((end_time - start_time) - expected_ns) / expected_ns;
                if (error_pct < 5.0) begin
                    $display("  PASS: frame timing within 5%%");
                    pass = pass + 1;
                end else begin
                    $display("  FAIL: frame timing error %.1f%%", error_pct);
                    fail = fail + 1;
                end
            end
        end

        // ════════════════════════════════════════════════
        // TEST 7: Random byte transmission
        // ════════════════════════════════════════════════
        $display("\n[TEST 7] Random byte transmission");
        for (k = 0; k < 10; k = k + 1) begin
            send_and_check($random & 8'hFF, "random");
        end

        // ════════════════════════════════════════════════
        // TEST 8: X propagation
        // ════════════════════════════════════════════════
        $display("\n[TEST 8] X propagation");
        rst_n = 0; repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
        data_in = 8'hXX; send = 1; @(posedge clk); send = 0;
        // Wait for busy to go high then low
        @(posedge busy); @(negedge busy); #1;
        if (tx !== 1'bx) begin
            $display("  FAIL: tx not X after X data");
            fail = fail + 1;
        end else begin
            $display("  PASS: X propagated in tx");
            pass = pass + 1;
        end

        // ── Summary ──────────────────────────────────────
        $display("\n════════════════════════════════");
        $display("  uart_tx: %0d passed, %0d failed", pass, fail);
        $display("════════════════════════════════\n");
        $finish;
    end

    initial begin #10_000_000; $display("TIMEOUT"); $finish; end

endmodule