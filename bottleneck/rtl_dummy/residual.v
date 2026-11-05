`timescale 1ns/1ps
module residual #(parameter integer BITWIDTH = 16)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire in_valid,
    output wire in_ready,
    input wire signed [BITWIDTH-1:0] in_data,
    input wire skip_valid,
    output wire skip_ready,
    input wire signed [BITWIDTH-1:0] skip_data,
    output reg out_valid,
    input wire out_ready,
    output reg signed [BITWIDTH-1:0] out_data
);
reg signed [BITWIDTH-1:0] main_buffer, skip_buffer;
reg have_main, have_skip;
assign in_ready = nrst && !out_valid && !have_main;
assign skip_ready = nrst && enable && !out_valid && !have_skip;

function automatic signed [15:0] saturate16(input signed [63:0] value);
    if (value > 32767) saturate16 = 16'sh7fff;
    else if (value < -32768) saturate16 = 16'sh8000;
    else saturate16 = value[15:0];
endfunction

task automatic compute;
    reg signed [63:0] total;
    begin
        if (enable) begin
            total = $signed(main_buffer);
            total = total + $signed(skip_buffer);
            out_data <= saturate16(total);
        end else out_data <= main_buffer;
        out_valid <= 1;
        have_main = 0;
        have_skip = 0;
    end
endtask

always @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        out_valid <= 0; out_data <= 0;
        main_buffer = 0; skip_buffer = 0;
        have_main = 0; have_skip = 0;
    end else begin
        if (out_valid && out_ready) out_valid <= 0;
        if (in_valid && in_ready) begin main_buffer = in_data; have_main = 1; end
        if (skip_valid && skip_ready) begin skip_buffer = skip_data; have_skip = 1; end
        if (have_main && (!enable || have_skip)) compute();
    end
end
endmodule
