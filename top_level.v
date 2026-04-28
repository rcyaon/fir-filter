//========================================================================
// top_level
//========================================================================

`ifndef TOP_LEVEL_V
`define TOP_LEVEL_V

`include "fir_filter-misc.v"

module top_level (
    input  wire clk_27mhz,      // onboard 27 MHz oscillator
    input  wire rst_n,           // active-low reset (button S1)
    output wire uart_txd,        // UART TX → USB-serial RX pin
    output wire [5:0] led        // debug LEDs (active low on Tang Nano)
);

// adder tree stuff 

endmodule

`endif /* TOP_LEVEL_V */