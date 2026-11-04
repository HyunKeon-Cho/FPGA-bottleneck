`timescale 1ns/1ps
module tb_core;
    // ----------------------------------------------------------------
    // signals
    // ----------------------------------------------------------------
    reg	clk = 0;
    reg	nrst = 0;
    always #5 clk = ~clk;
    wire [4:0]	iv;
    wire [4:0]	il;
    reg [4:0]	ordy = 0;
    wire [4:0]	ir;
    wire [4:0]	ov;
    wire signed [15:0]	idata [0:4];
    wire signed [15:0]	odata [0:4];
    wire	iteration;

    reg	start = 0;
    wire	done;
    reg	pool_enable = 0;
    wire	stage_valid;
    reg	stage_ready = 0;
    wire integer	stage_id;
    wire integer	stage_unit;
    wire integer	stage_start;
    wire integer	stage_size;

    // ----------------------------------------------------------------
    // scoreboard and case configuration
    // ----------------------------------------------------------------
    // File data feeds the controller; captured data is an independent scoreboard.
    reg signed [15:0]	inputs [0:415];
    reg signed [15:0]	weights [0:135];
    reg signed [15:0]	outputs [0:199];
    reg signed [15:0]	captured [0:4][0:1023];
    reg signed [15:0]	expected [0:1023];
    integer	received [0:4];
    integer	sent [0:4];
    integer	stalled [0:4];
    integer	input_wait [0:4];
    reg [4:0]	was_stalled = 0;
    reg signed [15:0]	held [0:4];
    integer	cycle = 0;
    integer	monitor_index;
    integer	ready_index;
    integer	case_id;
    integer	h;
    integer	input_offset;
    integer	kernel_offset;
    integer	i;
    reg	random_mode = 1;
    reg [31:0]	random_state = 32'h5eed1234;

    // ----------------------------------------------------------------
    // instances
    // ----------------------------------------------------------------
    mac m (
        .clk			(clk),
        .nrst			(nrst),
        .iteration		(iteration),
        .in_valid		(iv[0]),
        .in_ready		(ir[0]),
        .in_data		(idata[0]),
        .in_last		(il[0]),
        .out_valid		(ov[0]),
        .out_ready		(ordy[0]),
        .out_data		(odata[0])
    );

    relu r (
        .clk			(clk),
        .nrst			(nrst),
        .in_valid		(iv[1]),
        .in_ready		(ir[1]),
        .in_data		(idata[1]),
        .in_last		(il[1]),
        .out_valid		(ov[1]),
        .out_ready		(ordy[1]),
        .out_data		(odata[1])
    );

    pooling p (
        .clk			(clk),
        .nrst			(nrst),
        .in_valid		(iv[2]),
        .in_ready		(ir[2]),
        .in_data		(idata[2]),
        .in_last		(il[2]),
        .out_valid		(ov[2]),
        .out_ready		(ordy[2]),
        .out_data		(odata[2])
    );

    residual s (
        .clk			(clk),
        .nrst			(nrst),
        .in_valid		(iv[3]),
        .in_ready		(ir[3]),
        .in_data		(idata[3]),
        .in_last		(il[3]),
        .out_valid		(ov[3]),
        .out_ready		(ordy[3]),
        .out_data		(odata[3])
    );

    general_average_pooling g (
        .clk			(clk),
        .nrst			(nrst),
        .in_valid		(iv[4]),
        .in_ready		(ir[4]),
        .in_data		(idata[4]),
        .in_last		(il[4]),
        .out_valid		(ov[4]),
        .out_ready		(ordy[4]),
        .out_data		(odata[4])
    );


    embedded_controller controller (
        .clk			(clk),
        .nrst			(nrst),
        .start			(start),
        .h				(h),
        .input_offset	(input_offset),
        .kernel_offset	(kernel_offset),
        .pool_enable	(pool_enable),
        .inputs			(inputs),
        .weights		(weights),
        .iv				(iv),
        .il				(il),
        .idata			(idata),
        .iteration		(iteration),
        .ir				(ir),
        .ov				(ov),
        .ordy			(ordy),
        .odata			(odata),
        .stage_valid	(stage_valid),
        .stage_ready	(stage_ready),
        .stage_id		(stage_id),
        .stage_unit		(stage_unit),
        .stage_start	(stage_start),
        .stage_size		(stage_size),
        .done			(done)
    );

    // ----------------------------------------------------------------
    // backpressure
    // ----------------------------------------------------------------
    // Reproducible pseudo-random stalls, including stretches of backpressure.
    always @(negedge clk) begin
        if (!nrst) ordy = 0;
        else if (random_mode) begin
            random_state = (random_state >> 1) ^ (32'hd0000001 & {32{random_state[0]}});
            for (ready_index = 0; ready_index < 5; ready_index = ready_index + 1)
                ordy[ready_index] = (cycle % 19 >= 6) && random_state[ready_index];
        end
    end

    // ----------------------------------------------------------------
    // output monitor
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!nrst) begin
            cycle <= 0;
            was_stalled <= 0;
            for (monitor_index = 0; monitor_index < 5; monitor_index = monitor_index + 1) begin
                received[monitor_index] <= 0;
                sent[monitor_index] <= 0;
                stalled[monitor_index] <= 0;
                input_wait[monitor_index] <= 0;
            end
        end else begin
            cycle <= cycle + 1;
            for (monitor_index = 0; monitor_index < 5; monitor_index = monitor_index + 1) begin
                if (was_stalled[monitor_index] &&
                    (!ov[monitor_index] || odata[monitor_index] !== held[monitor_index]))
                    $fatal(1, "[ ERROR ] Output changed under backpressure, unit %0d", monitor_index);
                was_stalled[monitor_index] <= ov[monitor_index] && !ordy[monitor_index];
                held[monitor_index] <= odata[monitor_index];
                if (iv[monitor_index] && ir[monitor_index]) sent[monitor_index] <= sent[monitor_index] + 1;
                if (iv[monitor_index] && !ir[monitor_index]) input_wait[monitor_index] <= input_wait[monitor_index] + 1;
                if (ov[monitor_index] && !ordy[monitor_index]) stalled[monitor_index] <= stalled[monitor_index] + 1;
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
    // check tasks
    // ----------------------------------------------------------------
    task automatic check_one (
        input integer		unit_id,
        input integer		index,
        input signed [15:0]	value
    );
        begin
            await_count(unit_id, index + 1);
            if (captured[unit_id][index] !== value)
                $fatal(1, "[ ERROR ] Directed unit=%0d got=%0d expected=%0d", unit_id, $signed(captured[unit_id][index]), value);
        end
    endtask

    task automatic check_stage (
        input integer	unit_id,
        input integer	start,
        input integer	size,
        input string	stage_name
    );
        integer	t;
        integer	file_id;
        string	path;
        begin
            await_count(unit_id, start + size);
            path = $sformatf("../../../../utiles/data/case%0d_%s.txt", case_id, stage_name);
            $readmemh(path, expected, 0, size - 1);
            file_id = $fopen($sformatf("case%0d_%s_actual.txt", case_id, stage_name), "w");
            for (t = 0; t < size; t = t + 1) begin
                if (captured[unit_id][start + t] !== expected[t])
                    $fatal(1, "[ ERROR ] case%0d %s index=%0d actual=%0d ref=%0d", case_id, stage_name, t,
                           $signed(captured[unit_id][start + t]), $signed(expected[t]));
                if (stage_name == "output" &&
                    captured[unit_id][start + t] !== outputs[(case_id == 0 ? 0 : 128) + t])
                    $fatal(1, "[ ERROR ] Bench output mismatch");
                $fdisplay(file_id, "%04h", captured[unit_id][start + t]);
            end
            $fclose(file_id);
            $display("[ PASS ] case%0d %s (%0d values)", case_id, stage_name, size);
        end
    endtask

    // ----------------------------------------------------------------
    // stage checker
    // ----------------------------------------------------------------
    function automatic string stage_label (
        input integer	id
    );
        case (id)
            0: stage_label = "conv1";
            1: stage_label = "relu1";
            2: stage_label = "conv2";
            3: stage_label = "relu2";
            4: stage_label = "conv3";
            5: stage_label = "residual";
            6: stage_label = "relu3";
            7: stage_label = "pool";
            8: stage_label = "output";
            9: stage_label = "gap";
            default: stage_label = "unknown";
        endcase
    endfunction

    // Acknowledge only after checking the independently observed HDL output.
    initial begin
        forever begin
            @(posedge stage_valid);
            check_stage(stage_unit, stage_start, stage_size, stage_label(stage_id));
            stage_ready = 1;
            @(negedge stage_valid);
            stage_ready = 0;
        end
    end

    // ----------------------------------------------------------------
    // reset
    // ----------------------------------------------------------------
    task automatic reset_all;
        begin
            @(negedge clk);
            nrst = 0;
            repeat (3) @(negedge clk);
            nrst = 1;
        end
    endtask

    // ----------------------------------------------------------------
    // watchdog
    // ----------------------------------------------------------------
    initial begin
        // Stop the simulation if a handshake deadlock occurs.
        #20000000;
        $fatal(1, "[ ERROR ] Handshake timeout");
    end

    // ----------------------------------------------------------------
    // test sequence
    // ----------------------------------------------------------------
    initial begin
        $display("----------------------------------------------------------------");
        $display("[1/3] Checking reset and directed arithmetic...");
        $display("----------------------------------------------------------------");

        reset_all();
        // Reset while MAC/GAP/pool/residual hold partial work and ReLU holds an output.
        random_mode = 0;
        ordy = 0;
        controller.send_word(0, 1000, 0, 0);
        controller.send_word(0, 2000, 0, 1);
        controller.send_word(2, -100, 0, 0);
        controller.send_word(3, 100, 0, 0);
        controller.send_word(4, 100, 0, 0);
        controller.send_word(1, 123, 0, 0);
        reset_all();
        random_mode = 1;
        // Directed signed arithmetic: both saturation signs, tie rounding, max of negatives.
        controller.send_word(0, 32767, 0, 0);
        controller.send_word(0, 32767, 1, 1);
        check_one(0, 0, 32767);
        controller.send_word(0, -32768, 0, 0);
        controller.send_word(0, 32767, 1, 1);
        check_one(0, 1, -32768);
        controller.send_word(0, 1, 0, 0);
        controller.send_word(0, 128, 1, 1);
        check_one(0, 2, 1);
        controller.send_word(0, -1, 0, 0);
        controller.send_word(0, 128, 1, 1);
        check_one(0, 3, -1);
        controller.send_word(1, -32768, 0, 0);
        check_one(1, 0, 0);
        controller.send_word(1, 32767, 1, 0);
        check_one(1, 1, 32767);
        controller.send_word(2, -50, 0, 0);
        controller.send_word(2, -200, 0, 0);
        controller.send_word(2, -2, 0, 0);
        controller.send_word(2, -8, 1, 0);
        check_one(2, 0, -2);
        controller.send_word(3, 32767, 0, 0);
        controller.send_word(3, 256, 1, 0);
        check_one(3, 0, 32767);
        controller.send_word(3, -32768, 0, 0);
        controller.send_word(3, -256, 1, 0);
        check_one(3, 1, -32768);
        controller.send_word(4, -1, 0, 0);
        controller.send_word(4, 0, 1, 0);
        check_one(4, 0, -1);
        controller.send_word(4, 1, 0, 0);
        controller.send_word(4, 0, 1, 0);
        check_one(4, 1, 1);
        $display("[ PASS ] directed arithmetic and reset-in-flight");
        reset_all();

        $display("----------------------------------------------------------------");
        $display("[2/3] Checking bottleneck cases...");
        $display("----------------------------------------------------------------");

        $readmemh("../data/input.txt", inputs);
        $readmemh("../data/kernel.txt", weights);
        $readmemh("../data/output.txt", outputs);
        input_offset = 0;
        for (case_id = 0; case_id < 2; case_id = case_id + 1) begin
            h = case_id == 0 ? 4 : 6;
            kernel_offset = case_id * 68;
            pool_enable = case_id == 1;
            @(negedge clk);
            start = 1;
            wait (done);
            @(negedge clk);
            start = 0;
            wait (!done);
            input_offset = input_offset + h * h * 8;
        end
        repeat (30) @(negedge clk);

        $display("----------------------------------------------------------------");
        $display("[3/3] Checking handshake totals...");
        $display("----------------------------------------------------------------");

        // Exactly one result per dot/window/pair/channel, and one per ReLU input.
        if (received[0] != 624 || received[1] != 624 || received[2] != 72 || received[3] != 416 || received[4] != 16)
            $fatal(1, "[ ERROR ] Final output count mismatch");
        for (i = 0; i < 5; i = i + 1) begin
            $display("[ INFO ] HANDSHAKE unit=%0d in=%0d out=%0d output_stall=%0d input_wait=%0d", i, sent[i], received[i], stalled[i], input_wait[i]);
            if (stalled[i] == 0 || input_wait[i] == 0) $fatal(1, "[ ERROR ] Backpressure not exercised");
        end
        $display("[ PASS ] ALL TESTS PASSED");
        $finish;
    end
endmodule
