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
reg signed [BITWIDTH-1:0] input_buffer [0:30];
reg signed [BITWIDTH-1:0] output_buffer [0:30];
integer input_count, output_index, output_length;
assign in_ready = nrst && !out_valid;


task automatic compute;
    integer i;
    reg signed [63:0] total;
    reg signed [BITWIDTH-1:0] maximum;
    begin
        if (enable) begin
            maximum = input_buffer[0];
            for (i = 1; i < iteration; i = i + 1)
                if (input_buffer[i] > maximum) maximum = input_buffer[i];
            output_buffer[0] = maximum;
            output_length = 1;
        end else begin
            for (i = 0; i < iteration; i = i + 1) output_buffer[i] = input_buffer[i];
            output_length = iteration;
        end
        output_index = 0;
        out_data <= output_buffer[0];
        out_valid <= 1;
    end
endtask

always @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        input_count = 0; output_index = 0; output_length = 0;
        out_valid <= 0; out_data <= 0;
    end else begin
        if (out_valid && out_ready) begin
            if (output_index + 1 < output_length) begin
                output_index = output_index + 1;
                out_data <= output_buffer[output_index];
            end else begin
                out_valid <= 0;
                output_index = 0;
                output_length = 0;
            end
        end
        if (in_valid && in_ready) begin
            input_buffer[input_count] = in_data;
            input_count = input_count + 1;
            if (input_count == iteration) begin
                compute();
                input_count = 0;
            end
        end
    end
end
endmodule
