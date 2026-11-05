`timescale 1ns/1ps
// Simulation-only controller model. Task execution does not model hardware latency.
// Reference comparisons and file I/O belong to tb_core.
module embedded_controller (
    input wire	clk,
    input wire	nrst,
    input wire	start,
    input integer	h,
    input wire signed [15:0]	inputs [0:287],
    input wire signed [15:0]	weights [0:67],

    output wire mac_in_valid,
    input wire mac_in_ready,
    output wire signed [15:0] mac_in_data,
    output wire mac_in_last,
    input wire mac_out_valid,
    input wire mac_out_ready,
    input wire signed [15:0] mac_out_data,

    output wire relu_in_valid,
    input wire relu_in_ready,
    output wire signed [15:0] relu_in_data,
    output wire relu_in_last,
    input wire relu_out_valid,
    input wire relu_out_ready,
    input wire signed [15:0] relu_out_data,

    output wire pooling_in_valid,
    input wire pooling_in_ready,
    output wire signed [15:0] pooling_in_data,
    output wire pooling_in_last,
    input wire pooling_out_valid,
    input wire pooling_out_ready,
    input wire signed [15:0] pooling_out_data,

    output wire residual_in_valid,
    input wire residual_in_ready,
    output wire signed [15:0] residual_in_data,
    output wire residual_in_last,
    input wire residual_out_valid,
    input wire residual_out_ready,
    input wire signed [15:0] residual_out_data,

    output wire gap_in_valid,
    input wire gap_in_ready,
    output wire signed [15:0] gap_in_data,
    output wire gap_in_last,
    input wire gap_out_valid,
    input wire gap_out_ready,
    input wire signed [15:0] gap_out_data,

    output reg mac_iteration,

    output reg	stage_valid,
    input wire	stage_ready,
    output integer	stage_id,
    output integer	stage_unit,
    output integer	stage_start,
    output integer	stage_size,
    output reg	done
);
    // Indexed views used only by the generic transfer/collection tasks.
    reg [4:0] unit_in_valid;
    reg [4:0] unit_in_last;
    reg signed [15:0] unit_in_data [0:4];
    wire [4:0] unit_in_ready;
    wire [4:0] unit_out_valid;
    wire [4:0] unit_out_ready;
    wire signed [15:0] unit_out_data [0:4];
    assign {gap_in_valid, residual_in_valid, pooling_in_valid, relu_in_valid, mac_in_valid} = unit_in_valid;
    assign {gap_in_last, residual_in_last, pooling_in_last, relu_in_last, mac_in_last} = unit_in_last;
    assign unit_in_ready = {gap_in_ready, residual_in_ready, pooling_in_ready, relu_in_ready, mac_in_ready};
    assign unit_out_valid = {gap_out_valid, residual_out_valid, pooling_out_valid, relu_out_valid, mac_out_valid};
    assign unit_out_ready = {gap_out_ready, residual_out_ready, pooling_out_ready, relu_out_ready, mac_out_ready};
    assign mac_in_data = unit_in_data[0];
    assign unit_out_data[0] = mac_out_data;
    assign relu_in_data = unit_in_data[1];
    assign unit_out_data[1] = relu_out_data;
    assign pooling_in_data = unit_in_data[2];
    assign unit_out_data[2] = pooling_out_data;
    assign residual_in_data = unit_in_data[3];
    assign unit_out_data[3] = residual_out_data;
    assign gap_in_data = unit_in_data[4];
    assign unit_out_data[4] = gap_out_data;

    // ----------------------------------------------------------------
    // memories and counters
    // ----------------------------------------------------------------
    reg signed [15:0]	feature [0:287];
    reg signed [15:0]	skip [0:287];
    reg signed [15:0]	captured [0:4][0:431];
    integer	received [0:4];
    integer	cycle = 0;
    integer	monitor_index;
    integer	init_index;

    // ----------------------------------------------------------------
    // output collection
    // ----------------------------------------------------------------
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            cycle <= 0;
            for (monitor_index = 0; monitor_index < 5; monitor_index = monitor_index + 1)
                received[monitor_index] <= 0;
        end else begin
            cycle <= cycle + 1;
            for (monitor_index = 0; monitor_index < 5; monitor_index = monitor_index + 1) begin
                if (unit_out_valid[monitor_index] && unit_out_ready[monitor_index]) begin
                    captured[monitor_index][received[monitor_index]] <= unit_out_data[monitor_index];
                    received[monitor_index] <= received[monitor_index] + 1;
                end
            end
        end
    end

    // Abort the entire task stack, including blocked transfers/stage handoffs.
    // A reset cancels the case; the caller must lower start and issue a fresh edge.
    always @(negedge nrst) begin
        disable case_execution;
        unit_in_valid = 0;
        unit_in_last = 0;
        mac_iteration = 0;
        stage_valid = 0;
        stage_id = 0;
        stage_unit = 0;
        stage_start = 0;
        stage_size = 0;
        done = 0;
        for (init_index = 0; init_index < 5; init_index = init_index + 1)
            unit_in_data[init_index] = 0;
    end

    // ----------------------------------------------------------------
    // transfer tasks
    // ----------------------------------------------------------------
    task automatic send_word (
        input integer		unit_id,
        input signed [15:0]	value,
        input				last,
        input				phase
    );
        begin
            // Drive on falling edge; retain all fields until a rising-edge transfer.
            @(negedge clk);
            if ((cycle + unit_id) % 7 == 0) @(negedge clk);
            unit_in_valid[unit_id] = 1;
            unit_in_data[unit_id] = value;
            unit_in_last[unit_id] = last;
            if (unit_id == 0) mac_iteration = phase;
            @(posedge clk);
            while (!unit_in_ready[unit_id]) @(posedge clk);
            @(negedge clk);
            unit_in_valid[unit_id] = 0;
            unit_in_last[unit_id] = 0;
        end
    endtask

    task automatic await_count (
        input integer	unit_id,
        input integer	target
    );
        begin
            @(negedge clk);
            while (received[unit_id] < target) @(negedge clk);
        end
    endtask

    // ----------------------------------------------------------------
    // stage handoff
    // ----------------------------------------------------------------
    // Hold stage metadata until the TB has checked and acknowledged the stage.
    task automatic report_stage (
        input integer	unit_id,
        input integer	first,
        input integer	size,
        input integer	stage
    );
        begin
            stage_unit = unit_id;
            stage_start = first;
            stage_size = size;
            stage_id = stage;
            stage_valid = 1;
            wait (stage_ready);
            @(negedge clk);
            stage_valid = 0;
            wait (!stage_ready);
        end
    endtask

    task automatic finish_layer (
        input integer	unit_id,
        input integer	first,
        input integer	size,
        input integer	stage
    );
        integer	t;
        begin
            await_count(unit_id, first + size);
            for (t = 0; t < size; t = t + 1)
                feature[t] = captured[unit_id][first + t];
            report_stage(unit_id, first, size, stage);
        end
    endtask

    // ----------------------------------------------------------------
    // layer tasks
    // ----------------------------------------------------------------
    // NHWC source -> [output y,x,channel][kernel y,x,input channel] dot streams.
    // Weight layout is O,KY,KX,I. Padding is inserted here, outside MAC.
    task automatic convolution (
        input integer	cin,
        input integer	cout,
        input integer	ks,
        input integer	weight_base,
        input integer	stage
    );
        integer	y;
        integer	x;
        integer	oc;
        integer	ky;
        integer	kx;
        integer	ic;
        integer	iy;
        integer	ix;
        integer	base;
        reg signed [15:0]	activation;
        begin
            base = received[0];
            for (y = 0; y < h; y = y + 1)
                for (x = 0; x < h; x = x + 1)
                    for (oc = 0; oc < cout; oc = oc + 1)
                        for (ky = 0; ky < ks; ky = ky + 1)
                            for (kx = 0; kx < ks; kx = kx + 1)
                                for (ic = 0; ic < cin; ic = ic + 1) begin
                                    iy = y + ky - ks / 2;
                                    ix = x + kx - ks / 2;
                                    activation = 0;
                                    if (iy >= 0 && iy < h && ix >= 0 && ix < h)
                                        activation = feature[(iy * h + ix) * cin + ic];
                                    send_word(0, activation, 0, 0);
                                    send_word(0, weights[weight_base + ((oc * ks + ky) * ks + kx) * cin + ic],
                                              ky == ks - 1 && kx == ks - 1 && ic == cin - 1, 1);
                                end
            finish_layer(0, base, h * h * cout, stage);
        end
    endtask

    task automatic activate (
        input integer	size,
        input integer	stage
    );
        integer	t;
        integer	base;
        begin
            base = received[1];
            for (t = 0; t < size; t = t + 1) send_word(1, feature[t], t == size - 1, 0);
            finish_layer(1, base, size, stage);
        end
    endtask

    task automatic add_skip;
        integer	t;
        integer	base;
        begin
            base = received[3];
            for (t = 0; t < h * h * 8; t = t + 1) begin
                send_word(3, feature[t], 0, 0);
                send_word(3, skip[t], 1, 0);
            end
            finish_layer(3, base, h * h * 8, 5);
        end
    endtask

    task automatic max_pool;
        integer	y;
        integer	x;
        integer	c;
        integer	dy;
        integer	dx;
        integer	base;
        begin
            base = received[2];
            for (y = 0; y < h; y = y + 2)
                for (x = 0; x < h; x = x + 2)
                    for (c = 0; c < 8; c = c + 1)
                        for (dy = 0; dy < 2; dy = dy + 1)
                            for (dx = 0; dx < 2; dx = dx + 1)
                                send_word(2, feature[((y + dy) * h + x + dx) * 8 + c], dy == 1 && dx == 1, 0);
            finish_layer(2, base, (h / 2) * (h / 2) * 8, 7);
        end
    endtask

    task automatic global_average (
        input integer	spatial_size
    );
        integer	c;
        integer	t;
        integer	base;
        begin
            base = received[4];
            for (c = 0; c < 8; c = c + 1)
                for (t = 0; t < spatial_size; t = t + 1)
                    send_word(4, feature[t * 8 + c], t == spatial_size - 1, 0);
            finish_layer(4, base, 8, 8);
        end
    endtask

    // ----------------------------------------------------------------
    // case execution
    // ----------------------------------------------------------------
    task automatic run_bottleneck;
        integer	t;
        begin
            for (t = 0; t < h * h * 8; t = t + 1) begin
                feature[t] = inputs[t];
                skip[t] = feature[t];
            end
            convolution(8, 2, 1, 0, 0);
            activate(h * h * 2, 1);
            convolution(2, 2, 3, 16, 2);
            activate(h * h * 2, 3);
            convolution(2, 8, 1, 52, 4);
            add_skip();
            activate(h * h * 8, 6);
            max_pool();
            global_average((h / 2) * (h / 2));
        end
    endtask

    initial begin
        unit_in_valid = 0;
        unit_in_last = 0;
        mac_iteration = 0;
        stage_valid = 0;
        stage_id = 0;
        stage_unit = 0;
        stage_start = 0;
        stage_size = 0;
        done = 0;
        for (init_index = 0; init_index < 5; init_index = init_index + 1)
            unit_in_data[init_index] = 0;
        forever begin : case_execution
            wait (nrst === 1'b1);
            wait (start === 1'b0);
            @(posedge start);
            if (nrst) begin
                run_bottleneck();
                done = 1;
                @(negedge start);
                done = 0;
            end
        end
    end
endmodule
