`timescale 1ns/1ps
module mac #(
    parameter integer BITWIDTH = 16
)(
    input  wire                         clk, 
    input  wire                         nrst,
    input  wire                         iteration,
    input  wire                         in_valid, 
    output wire                         in_ready,
    input  wire signed [BITWIDTH-1:0]   in_data,
    input  wire                         in_last,
    output reg                          out_valid, 
    input  wire                         out_ready,
    output reg  signed [BITWIDTH-1:0]  out_data
);

// Behavioral, simulation-only dummy. All external transfers require valid && ready.
// Output and valid remain stable until accepted. No TB hierarchy accesses.
// Behavioral dummy arithmetic: sign + 7 integer bits + 8 fractional bits.
// Round nearest, ties away from zero; saturate at every module output.
function automatic signed [15:0] sat16(input signed [63:0] value);
    if (value > 32767) sat16 = 16'sh7fff;
    else if (value < -32768) sat16 = 16'sh8000;
    else sat16 = value[15:0];
endfunction

function automatic signed [63:0] round_div(
    input signed [63:0] value, input signed [63:0] divisor);
    if (value < 0) round_div = -((-value + divisor/2) / divisor);
    else round_div = (value + divisor/2) / divisor;
endfunction
reg signed [15:0] first;
reg have_first;
reg signed [63:0] accumulator;
integer count;
assign in_ready = nrst && (!out_valid || out_ready);

// iteration=0: activation; iteration=1: weight. in_last marks the last weight.
// Accumulate full products (16 fractional bits); round/saturate once per dot product.
task automatic compute(input signed [15:0] value, input weight_phase, input last);
    reg signed [63:0] product, total;
    begin
        if (!weight_phase) begin first = value; have_first = 1; end
        else if (have_first) begin
            product = $signed(first) * $signed(value);
            total = accumulator + product;
            have_first = 0;
            if (last) begin
                out_data <= sat16(round_div(total,256));
                out_valid <= 1;
                accumulator = 0;
            end else accumulator = total;
        end
    end
endtask

always @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        out_valid <= 0; out_data <= 0;
        first = 0; have_first = 0; accumulator = 0; count = 0;
    end else begin
        if (out_valid && out_ready) out_valid <= 0;
        if (in_valid && in_ready) compute(in_data, iteration, in_last);
    end
end
initial if (BITWIDTH != 16) $fatal(1,"Dummy format requires BITWIDTH=16 (Q7.8)");
endmodule
