`timescale 1ns/1ps
// Task-based behavioral model. Configuration is stable for a complete phase.
// One group is collected, then drained before any subsequent group is accepted.
module pooling #(parameter integer BITWIDTH = 16)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire [4:0] iteration,
    input wire in_valid,
    output wire in_ready,
    input wire signed [BITWIDTH-1:0] in_data,
    output reg out_valid,
    input wire out_ready,
    output reg signed [BITWIDTH-1:0] out_data
);

endmodule
