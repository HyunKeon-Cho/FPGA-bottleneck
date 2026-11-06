`timescale 1ns/1ps
// Same-clock, valid-only stream. Configuration stays stable until drained.
// collect_input and handle_output run every clock; registers separate stages.
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

    // ------------------------------------
    // Fixed-point arithmetic
    // ------------------------------------
    function automatic signed [BITWIDTH-1:0] saturate(input signed [63:0] value);
        reg signed [63:0] limit;
        begin
            limit = 64'sd1 <<< (BITWIDTH-1);
            if (value >= limit) saturate = limit - 1;
            else if (value < -limit) saturate = -limit;
            else saturate = value;
        end
    endfunction

    function automatic signed [63:0] rounded_divide(
        input signed [63:0] value,
        input integer divisor
    );
        begin
            if (value < 0) rounded_divide = -((-value + divisor/2) / divisor);
            else rounded_divide = (value + divisor/2) / divisor;
        end
    endfunction

    reg signed [63:0] accumulator;
    reg [4:0] input_count;
    reg pending_enable;
    reg signed [63:0] pending_sum;
    reg [4:0] pending_divisor;
    wire signed [63:0] extended_input = $signed(in_data);
    wire signed [63:0] total = accumulator + extended_input;

    task automatic collect_input;
        begin
            pending_enable <= 0;
            if (in_enable) begin
                if (!enable) begin
                    accumulator <= 0;
                    input_count <= 0;
                    pending_sum <= extended_input;
                    pending_divisor <= 1;
                    pending_enable <= 1;
                end else if (input_count == iteration - 1'b1) begin
                    pending_sum <= total;
                    pending_divisor <= iteration;
                    pending_enable <= 1;
                    accumulator <= 0;
                    input_count <= 0;
                end else begin
                    accumulator <= total;
                    input_count <= input_count + 1'b1;
                end
            end
        end
    endtask

    task automatic handle_output;
        begin
            out_enable <= pending_enable;
            if (pending_enable)
                out_data <= saturate(rounded_divide(pending_sum, pending_divisor));
        end
    endtask

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            accumulator <= 0;
            input_count <= 0;
            pending_sum <= 0;
            pending_divisor <= 1;
            pending_enable <= 0;
            out_enable <= 0;
            out_data <= 0;
        end else begin
            collect_input();
            handle_output();
        end
    end
endmodule
