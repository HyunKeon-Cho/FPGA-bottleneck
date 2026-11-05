`timescale 1ns/1ps
// Task-based behavioral model. Configuration is stable for a complete phase.
// One group is collected, then drained before any subsequent group is accepted.
module mac #(parameter integer BITWIDTH = 16)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire [4:0] iteration,
    input wire in_valid,
    output wire in_ready,
    input wire signed [BITWIDTH-1:0] in_data,
    input wire signed [BITWIDTH-1:0] kernel_data,
    output reg out_valid,
    input wire out_ready,
    output reg signed [BITWIDTH-1:0] out_data
);
reg signed [BITWIDTH-1:0] input_buffer [0:30];
reg signed [BITWIDTH-1:0] kernel_buffer [0:30];
reg signed [BITWIDTH-1:0] output_buffer [0:30];
integer input_count, output_index, output_length;
assign in_ready = nrst && !out_valid;

function automatic signed [15:0] saturate16(input signed [63:0] value);
    if (value > 32767) saturate16 = 16'sh7fff;
    else if (value < -32768) saturate16 = 16'sh8000;
    else saturate16 = value[15:0];
endfunction

function automatic signed [63:0] rounded_divide(input signed [63:0] value, input integer divisor);
    if (value < 0) rounded_divide = -((-value + divisor/2) / divisor);
    else rounded_divide = (value + divisor/2) / divisor;
endfunction

task automatic compute;
    integer i;
    reg signed [63:0] total;
    reg signed [BITWIDTH-1:0] maximum;
    begin
        if (enable) begin
            total = 0;
            for (i = 0; i < iteration; i = i + 1)
                total = total + $signed(input_buffer[i]) * $signed(kernel_buffer[i]);
            output_buffer[0] = saturate16(rounded_divide(total, 256));
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
            kernel_buffer[input_count] = kernel_data;
            input_count = input_count + 1;
            if (input_count == iteration) begin
                compute();
                input_count = 0;
            end
        end
    end
end
endmodule
