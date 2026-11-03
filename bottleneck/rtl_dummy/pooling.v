`timescale 1ns/1ps
module pooling #(
    parameter integer BITWIDTH = 16
)(
    input  wire                         clk, 
    input  wire                         nrst,
    input  wire                         in_valid, 
    output wire                         in_ready,
    input  wire signed [BITWIDTH-1:0]   in_data,
    input  wire                         in_last,
    output reg                          out_valid, 
    input  wire                         out_ready,
    output reg  signed [BITWIDTH-1:0]   out_data
);

// Behavioral, simulation-only dummy. All external transfers require valid && ready.
// Output and valid remain stable until accepted. No TB hierarchy accesses.
`include "fixed_math.vh"
reg signed [15:0] first;
reg have_first;
reg signed [63:0] accumulator;
integer count;
assign in_ready = nrst && (!out_valid || out_ready);

// TB sends one max-pool window (one channel); in_last ends that window.
task automatic compute(input signed [15:0] value, input last);
    reg signed [15:0] maximum;
    begin
        maximum = (count == 0 || value > first) ? value : first;
        if (last) begin out_data <= maximum; out_valid <= 1; count = 0; end
        else begin first = maximum; count = count + 1; end
    end
endtask

always @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        out_valid <= 0; out_data <= 0;
        first = 0; have_first = 0; accumulator = 0; count = 0;
    end else begin
        if (out_valid && out_ready) out_valid <= 0;
        if (in_valid && in_ready) compute(in_data, in_last);
    end
end
initial if (BITWIDTH != 16) $fatal(1,"Dummy format requires BITWIDTH=16 (Q7.8)");
endmodule
