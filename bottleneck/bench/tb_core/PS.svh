`ifndef PS_SVH
`define PS_SVH

    // ------------------------------------
    // Transfer State
    // ------------------------------------
    integer             cycle = 0;
    reg [31:0]          random_state = 32'h5eed1234;

    // ------------------------------------
    // Backpressure
    // ------------------------------------
    initial if ($value$plusargs("ready_seed=%d", random_state))
        $display("[ INFO ] ready seed=%0d", random_state);

    always @(negedge clk) begin
        if (!nrst) output_ready = 0;
        else begin
            random_state  = (random_state >> 1) ^ (32'hd0000001 & {32{random_state[0]}});
            output_ready = (cycle % 19 >= 6) && random_state[0];
        end
    end

    always @(posedge clk) begin
        if (!nrst) cycle <= 0;
        else cycle <= cycle + 1;
    end

    // ------------------------------------
    // phase1_setup
    // ------------------------------------
    task automatic phase1_setup;
        begin
            @(negedge clk);
            mac_enable        = 1;
            residual_enable   = 0;
            relu_enable       = 1;
            pooling_enable    = 0;
            gap_enable        = 0;
            mac_iteration     = 5'd8;
            pooling_iteration = 5'd4;
            gap_iteration     = 5'd9;
        end
    endtask

    // ------------------------------------
    // phase2_setup
    // ------------------------------------
    task automatic phase2_setup;
        begin
            @(negedge clk);
            mac_enable        = 1;
            residual_enable   = 0;
            relu_enable       = 1;
            pooling_enable    = 0;
            gap_enable        = 0;
            mac_iteration     = 5'd18;
            pooling_iteration = 5'd4;
            gap_iteration     = 5'd9;
        end
    endtask

    // ------------------------------------
    // phase3_setup
    // ------------------------------------
    task automatic phase3_setup;
        begin
            @(negedge clk);
            mac_enable        = 1;
            residual_enable   = 1;
            relu_enable       = 1;
            pooling_enable    = 1;
            gap_enable        = 1;
            mac_iteration     = 5'd2;
            pooling_iteration = 5'd4;
            gap_iteration     = 5'd9;
        end
    endtask
    
    // ------------------------------------
    // phase1_data_schedule
    // ------------------------------------
    task automatic phase1_data_schedule(
        input   reg signed [BITWIDTH-1:0] source_feature     [0:BUFFER_SIZE-1],
        input   reg signed [BITWIDTH-1:0] source_kernel      [0:BUFFER_SIZE-1],
        output  reg signed [BITWIDTH-1:0] scheduled_feature  [0:BUFFER_SIZE-1],
        output  reg signed [BITWIDTH-1:0] scheduled_kernel   [0:BUFFER_SIZE-1]
    );
        integer             pixel;
        integer             oc;
        integer             ic;
        integer             term;

        begin
            term = 0;
            for (pixel = 0; pixel < 36; pixel = pixel + 1)
                for (oc = 0; oc < 2; oc = oc + 1)
                    for (ic = 0; ic < 8; ic = ic + 1) begin
                        scheduled_feature[term] = source_feature[pixel*8+ic];
                        scheduled_kernel[term]  = source_kernel[oc*8+ic];
                        term                    = term + 1;
                    end
        end
    endtask

    // ------------------------------------
    // phase2_data_schedule
    // ------------------------------------
    task automatic phase2_data_schedule(
        input   reg signed [BITWIDTH-1:0] previous_output    [0:BUFFER_SIZE-1],
        input   reg signed [BITWIDTH-1:0] source_kernel      [0:BUFFER_SIZE-1],
        output  reg signed [BITWIDTH-1:0] scheduled_feature  [0:BUFFER_SIZE-1],
        output  reg signed [BITWIDTH-1:0] scheduled_kernel   [0:BUFFER_SIZE-1]
    );
        integer             y;
        integer             x;
        integer             oc;
        integer             ky;
        integer             kx;
        integer             ic;
        integer             iy;
        integer             ix;
        integer             term;

        begin
            term = 0;
            for (y = 0; y < 6; y = y + 1)
                for (x = 0; x < 6; x = x + 1)
                    for (oc = 0; oc < 2; oc = oc + 1)
                        for (ky = 0; ky < 3; ky = ky + 1)
                            for (kx = 0; kx < 3; kx = kx + 1)
                                for (ic = 0; ic < 2; ic = ic + 1) begin
                                    iy                      = y + ky - 1;
                                    ix                      = x + kx - 1;
                                    scheduled_feature[term] = 0;
                                    if (iy >= 0 && iy < 6 && ix >= 0 && ix < 6)
                                        scheduled_feature[term] = previous_output[(iy*6+ix)*2+ic];

                                    scheduled_kernel[term] = source_kernel[16+((oc*3+ky)*3+kx)*2+ic];
                                    term                   = term + 1;
                                end
        end
    endtask

    // ------------------------------------
    // phase3_data_schedule
    // ------------------------------------
    task automatic phase3_data_schedule(
        input   reg signed [BITWIDTH-1:0] previous_output    [0:BUFFER_SIZE-1],
        input   reg signed [BITWIDTH-1:0] source_kernel      [0:BUFFER_SIZE-1],
        input   reg signed [BITWIDTH-1:0] source_feature     [0:BUFFER_SIZE-1],
        output  reg signed [BITWIDTH-1:0] scheduled_feature  [0:BUFFER_SIZE-1],
        output  reg signed [BITWIDTH-1:0] scheduled_kernel   [0:BUFFER_SIZE-1],
        output  reg signed [BITWIDTH-1:0] scheduled_skip     [0:BUFFER_SIZE-1]
    );
        integer             oc;
        integer             wy;
        integer             wx;
        integer             dy;
        integer             dx;
        integer             ic;
        integer             y;
        integer             x;
        integer             term;
        integer             skip_index;

        begin
            term       = 0;
            skip_index = 0;

            // Channel -> pooling window -> top-left/right, bottom-left/right.
            for (oc = 0; oc < 8; oc = oc + 1)
                for (wy = 0; wy < 3; wy = wy + 1)
                    for (wx = 0; wx < 3; wx = wx + 1)
                        for (dy = 0; dy < 2; dy = dy + 1)
                            for (dx = 0; dx < 2; dx = dx + 1) begin
                                y                          = wy*2 + dy;
                                x                          = wx*2 + dx;
                                scheduled_skip[skip_index] = source_feature[(y*6+x)*8+oc];
                                skip_index                 = skip_index + 1;

                                for (ic = 0; ic < 2; ic = ic + 1) begin
                                    scheduled_feature[term] = previous_output[(y*6+x)*2+ic];
                                    scheduled_kernel[term]  = source_kernel[52+oc*2+ic];
                                    term                    = term + 1;
                                end
                            end
        end
    endtask

`endif // PS_SVH
