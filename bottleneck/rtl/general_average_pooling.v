`timescale 1ns/1ps
// Interface placeholder. Ports match rtl_dummy/general_average_pooling.v.
module general_average_pooling #(parameter integer BITWIDTH = 16)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire [4:0] iteration,
    input wire in_enable,
    input wire signed [BITWIDTH-1:0] in_data,
    output reg out_enable,
    output reg signed [BITWIDTH-1:0] out_data
);

endmodule
