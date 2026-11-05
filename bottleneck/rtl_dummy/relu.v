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
assign in_ready = nrst && !out_valid;

task automatic compute(input signed [BITWIDTH-1:0] value);
    begin
        out_data <= enable && value < 0 ? 0 : value;
        out_valid <= 1;
    end
endtask

always @(posedge clk or negedge nrst) begin
    if (!nrst) begin out_valid <= 0; out_data <= 0; end
    else begin
        if (out_valid && out_ready) out_valid <= 0;
        if (in_valid && in_ready) compute(in_data);
    end
end
endmodule
