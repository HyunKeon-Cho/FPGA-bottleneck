`timescale 1ns/1ps
module residual #(
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
    output reg  signed [BITWIDTH-1:0] out_data
);

// Behavioral, simulation-only dummy. All external transfers require valid && ready.
// Output and valid remain stable until accepted. No TB hierarchy accesses.
function automatic signed [15:0] sat16(input signed [63:0] value);
    if (value > 32767) sat16 = 16'sh7fff;
    else if (value < -32768) sat16 = 16'sh8000;
    else sat16 = value[15:0];
endfunction
reg signed [15:0] first;
reg have_first;
reg signed [63:0] accumulator;
integer count;
assign in_ready = nrst && (!out_valid || out_ready);

// First beat: main path. Second beat (in_last=1): skip path.
task automatic compute(input signed [15:0] value, input last);
    reg signed [63:0] total;
    begin
        if (!have_first) begin first = value; have_first = 1; end
        else if (last) begin
            total = $signed(first); total = total + $signed(value);
            out_data <= sat16(total); out_valid <= 1; have_first = 0;
        end
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
