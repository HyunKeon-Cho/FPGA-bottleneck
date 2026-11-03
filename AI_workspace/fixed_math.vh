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
