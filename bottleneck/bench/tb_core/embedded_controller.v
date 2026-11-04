`timescale 1ns/1ps
// Simulation-only controller model. Task execution does not model hardware latency.
// Reference comparisons and file I/O belong to tb_core.
module embedded_controller (
    input wire	clk,
    input wire	nrst,
    input wire	start,
    input integer	h,
    input integer	input_offset,
    input integer	kernel_offset,
    input wire	pool_enable,
    input wire signed [15:0]	inputs [0:415],
    input wire signed [15:0]	weights [0:135],

    output reg [4:0]	iv,
    output reg [4:0]	il,
    output reg signed [15:0]	idata [0:4],
    output reg	iteration,
    input wire [4:0]	ir,
    input wire [4:0]	ov,
    input wire [4:0]	ordy,
    input wire signed [15:0]	odata [0:4],

    output reg	stage_valid,
    input wire	stage_ready,
    output integer	stage_id,
    output integer	stage_unit,
    output integer	stage_start,
    output integer	stage_size,
    output reg	done
);
    // ----------------------------------------------------------------
    // memories and counters
    // ----------------------------------------------------------------
    reg signed [15:0]	feature [0:1023];
    reg signed [15:0]	skip [0:1023];
    reg signed [15:0]	captured [0:4][0:1023];
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
            iv = 0;
            il = 0;
            iteration = 0;
            for (monitor_index = 0; monitor_index < 5; monitor_index = monitor_index + 1)
                received[monitor_index] <= 0;
        end else begin
            cycle <= cycle + 1;
            for (monitor_index = 0; monitor_index < 5; monitor_index = monitor_index + 1) begin
                if (ov[monitor_index] && ordy[monitor_index]) begin
                    captured[monitor_index][received[monitor_index]] <= odata[monitor_index];
                    received[monitor_index] <= received[monitor_index] + 1;
                end
            end
        end
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
            iv[unit_id] = 1;
            idata[unit_id] = value;
            il[unit_id] = last;
            if (unit_id == 0) iteration = phase;
            @(posedge clk);
            while (!ir[unit_id]) @(posedge clk);
            @(negedge clk);
            iv[unit_id] = 0;
            il[unit_id] = 0;
        end
    endtask

    task automatic await_count (
        input integer	unit_id,
        input integer	target
    );
        begin
            @(negedge clk);
            while (received[unit_id] < target) @(negedge clk);
            if (received[unit_id] != target) $fatal(1, "[ ERROR ] Unexpected output count");
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
            finish_layer(4, base, 8, 9);
        end
    endtask

    // ----------------------------------------------------------------
    // case execution
    // ----------------------------------------------------------------
    task automatic run_bottleneck;
        integer	t;
        integer	size;
        integer	output_unit;
        begin
            for (t = 0; t < h * h * 8; t = t + 1) begin
                feature[t] = inputs[input_offset + t];
                skip[t] = feature[t];
            end
            convolution(8, 2, 1, kernel_offset, 0);
            activate(h * h * 2, 1);
            convolution(2, 2, 3, kernel_offset + 16, 2);
            activate(h * h * 2, 3);
            convolution(2, 8, 1, kernel_offset + 52, 4);
            add_skip();
            activate(h * h * 8, 6);
            if (pool_enable) max_pool();
            size = pool_enable ? (h / 2) * (h / 2) * 8 : h * h * 8;
            output_unit = pool_enable ? 2 : 1;
            report_stage(output_unit, received[output_unit] - size, size, 8);
            global_average(size / 8);
        end
    endtask

    initial begin
        iv = 0;
        il = 0;
        iteration = 0;
        stage_valid = 0;
        stage_id = 0;
        stage_unit = 0;
        stage_start = 0;
        stage_size = 0;
        done = 0;
        for (init_index = 0; init_index < 5; init_index = init_index + 1)
            idata[init_index] = 0;
        forever begin
            @(posedge start);
            run_bottleneck();
            done = 1;
            @(negedge start);
            done = 0;
        end
    end
endmodule
