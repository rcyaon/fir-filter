//========================================================================
// uart_tx
//========================================================================

// Simple 8N1 UART transmitter
// Baud rate = CLK_FREQ / BAUD_DIV
// Default: 27MHz / 234 ≈ 115200 baud

`ifndef UART_TX_V
`define UART_TX_V

module uart_tx #(
    parameter CLK_FREQ = 27_000_000,
    parameter BAUD     =    115_200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data_in,
    input  wire       send,       // Pulse high for 1 cycle to send a byte
    output reg        tx,
    output wire       busy
);

    localparam BAUD_DIV = CLK_FREQ / BAUD;  // 234

    reg [$clog2(BAUD_DIV)-1:0] baud_cnt;
    reg [9:0] shift_reg;   // {stop, data[7:0], start}
    reg [3:0] bit_cnt;
    reg       transmitting;

    assign busy = transmitting;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx           <= 1'b1;
            transmitting <= 1'b0;
            baud_cnt     <= 0;
            bit_cnt      <= 0;
            shift_reg    <= 10'h3FF;
        end else begin
            if (!transmitting && send) begin
                // Load: stop=1, data, start=0
                shift_reg    <= {1'b1, data_in, 1'b0};
                transmitting <= 1'b1;
                baud_cnt     <= 0;
                bit_cnt      <= 0;
            end else if (transmitting) begin
                if (baud_cnt == BAUD_DIV - 1) begin
                    baud_cnt <= 0;
                    tx       <= shift_reg[0];
                    shift_reg <= {1'b1, shift_reg[9:1]};
                    if (bit_cnt == 9) begin
                        transmitting <= 1'b0;
                    end else begin
                        bit_cnt <= bit_cnt + 1;
                    end
                end else begin
                    baud_cnt <= baud_cnt + 1;
                end
            end else begin
                tx <= 1'b1;
            end
        end
    end

endmodule

`endif /* UART_TX_V */