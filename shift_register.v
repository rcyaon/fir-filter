//========================================================================
// shift_register
//========================================================================

`ifndef SHIFT_REGISTER_V
`define SHIFT_REGISTER_V

// shift_register.v
// Tapped delay line for FIR filter

module shift_register #(
    parameter TAPS       = 16,
    parameter DATA_WIDTH = 16
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          sample_en,
    input  wire signed [DATA_WIDTH-1:0]  x_in,
    output wire signed [DATA_WIDTH-1:0]  taps [0:TAPS-1]
);

    reg signed [DATA_WIDTH-1:0] delay_line [0:TAPS-1];

    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < TAPS; i = i + 1)
                delay_line[i] <= 0;
        end 

        else if (sample_en) begin
            delay_line[0] <= x_in;
            for (i = 1; i < TAPS; i = i + 1)
                delay_line[i] <= delay_line[i-1];
        end
    end

    // wire outputs 
    genvar g;
    generate
        for (g = 0; g < TAPS; g = g + 1) begin : tap_out
            assign taps[g] = delay_line[g];
        end
    endgenerate

endmodule

`endif /* SHIFT_REGISTER_V */