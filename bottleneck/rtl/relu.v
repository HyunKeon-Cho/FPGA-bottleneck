`timescale 1ns/1ps
// Interface placeholder. Ports match rtl_dummy/relu.v.
module relu #(parameter integer BITWIDTH = 16)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire in_enable,
    input wire signed [BITWIDTH-1:0] in_data,
    output wire out_enable,
    output wire signed [BITWIDTH-1:0] out_data
);

endmodule
