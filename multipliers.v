//========================================================================
// multipliers
//========================================================================
//
// Does many multiplications at once: each filter coefficient times an input value for the FIR filter
// Filter numbers are loaded from coeffs.mem, where coefficient are precalculated. We look them up here --> Multiply

`ifndef MULTIPLIERS_V
`define MULTIPLIERS_V

`include "fir_filter-misc.v"

module multipliers #(
    parameter TAPS        = 16,
    parameter DATA_WIDTH  = 16,
    parameter COEFF_WIDTH = 16
)(
    input  wire                                        clk,
    input  wire                                        rst_n,
    input  wire signed [DATA_WIDTH-1:0]                taps [0:TAPS-1],
    output reg  signed [DATA_WIDTH+COEFF_WIDTH-1:0]    products [0:TAPS-1]
);

    localparam PROD_WIDTH = DATA_WIDTH + COEFF_WIDTH;

    reg signed [COEFF_WIDTH-1:0] coeffs [0:TAPS-1];
    initial $readmemh("coeffs.mem", coeffs);

    genvar g;
    generate
        for (g = 0; g < TAPS; g = g + 1) begin : mul_stage
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    products[g] <= 0;
                else
                    products[g] <= taps[g] * coeffs[g];
            end
        end
    endgenerate

endmodule

`endif /* MULTIPLIERS_V */