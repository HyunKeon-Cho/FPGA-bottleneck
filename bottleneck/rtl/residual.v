`timescale 1ns/1ps
// Interface placeholder. Ports match rtl_dummy/residual.v.
module residual #(parameter integer BITWIDTH = 16)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire in_enable,
    input wire signed [BITWIDTH-1:0] in_data,
    input wire signed [BITWIDTH-1:0] skip_data,
    output reg out_enable,
    output reg signed [BITWIDTH-1:0] out_data
);

endmodule
