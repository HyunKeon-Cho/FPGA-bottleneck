`timescale 1ns/1ps
module relu #(parameter integer BITWIDTH = 16)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire in_valid,
    output wire in_ready,
    input wire signed [BITWIDTH-1:0] in_data,
    output reg out_valid,
    input wire out_ready,
    output reg signed [BITWIDTH-1:0] out_data
);

endmodule