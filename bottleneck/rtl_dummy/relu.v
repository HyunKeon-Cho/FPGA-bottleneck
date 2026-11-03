`timescale 1ns/1ps
module relu #(
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

// Elementwise: in_last is unused, since the interface has no output framing.
task automatic compute(input signed [15:0] value);
    begin out_data <= value < 0 ? 16'sd0 : value; out_valid <= 1; end
endtask

always @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        out_valid <= 0; out_data <= 0;
        first = 0; have_first = 0; accumulator = 0; count = 0;
    end else begin
        if (out_valid && out_ready) out_valid <= 0;
        if (in_valid && in_ready) compute(in_data);
    end
end
initial if (BITWIDTH != 16) $fatal(1,"Dummy format requires BITWIDTH=16 (Q7.8)");
endmodule
