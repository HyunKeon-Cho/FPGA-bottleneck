`timescale 1ns/1ps
// Same-clock, valid-only stream. Configuration stays stable until drained.
// collect_input and handle_output run every clock; registers separate stages.
module relu #(parameter integer BITWIDTH = 16)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire in_enable,
    input wire signed [BITWIDTH-1:0] in_data,
    output reg out_enable,
    output reg signed [BITWIDTH-1:0] out_data
);

    reg pending_enable;
    reg signed [BITWIDTH-1:0] pending_data;

    task automatic collect_input;
        begin
            pending_enable <= in_enable;
            if (in_enable)
                pending_data <= (enable && in_data < 0) ? 0 : in_data;
        end
    endtask

    // ------------------------------------
    // Output stage (reads the previous clock's pending result)
    // ------------------------------------
    task automatic handle_output;
        begin
            out_enable <= pending_enable;
            if (pending_enable) out_data <= pending_data;
        end
    endtask

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            pending_enable <= 0;
            pending_data <= 0;
            out_enable <= 0;
            out_data <= 0;
        end else begin
            collect_input();
            handle_output();
        end
    end
endmodule
