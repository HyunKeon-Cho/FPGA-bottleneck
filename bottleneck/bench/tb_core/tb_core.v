`timescale 1ns/1ps
module tb_core;
    reg clk = 0;
    reg nrst = 0;
    always #5 clk = ~clk;

    reg mac_enable = 0, residual_enable = 0, relu_enable = 0;
    reg pooling_enable = 0, gap_enable = 0;
    reg [4:0] mac_iteration = 1, pooling_iteration = 4, gap_iteration = 9;
    reg mac_in_valid = 0;
    wire mac_in_ready;
    reg signed [15:0] mac_in_data = 0, mac_kernel_data = 0;
    wire mac_out_valid, mac_out_ready;
    wire signed [15:0] mac_out_data;
    wire residual_in_valid, residual_in_ready;
    wire signed [15:0] residual_in_data;
    reg residual_skip_valid = 0;
    wire residual_skip_ready;
    reg signed [15:0] residual_skip_data = 0;
    wire residual_out_valid, residual_out_ready;
    wire signed [15:0] residual_out_data;
    wire relu_in_valid, relu_in_ready;
    wire signed [15:0] relu_in_data;
    wire relu_out_valid, relu_out_ready;
    wire signed [15:0] relu_out_data;
    wire pooling_in_valid, pooling_in_ready;
    wire signed [15:0] pooling_in_data;
    wire pooling_out_valid, pooling_out_ready;
    wire signed [15:0] pooling_out_data;
    wire gap_in_valid, gap_in_ready;
    wire signed [15:0] gap_in_data;
    wire gap_out_valid;
    reg gap_out_ready = 0;
    wire signed [15:0] gap_out_data;

    // Every DUT output is connected to the next DUT's input.
    assign residual_in_valid = mac_out_valid;
    assign residual_in_data = mac_out_data;
    assign mac_out_ready = residual_in_ready;
    assign relu_in_valid = residual_out_valid;
    assign relu_in_data = residual_out_data;
    assign residual_out_ready = relu_in_ready;
    assign pooling_in_valid = relu_out_valid;
    assign pooling_in_data = relu_out_data;
    assign relu_out_ready = pooling_in_ready;
    assign gap_in_valid = pooling_out_valid;
    assign gap_in_data = pooling_out_data;
    assign pooling_out_ready = gap_in_ready;

    mac u_mac (
        .clk(clk), .nrst(nrst), .enable(mac_enable), .iteration(mac_iteration),
        .in_valid(mac_in_valid), .in_ready(mac_in_ready), .in_data(mac_in_data),
        .kernel_data(mac_kernel_data), .out_valid(mac_out_valid),
        .out_ready(mac_out_ready), .out_data(mac_out_data)
    );
    residual u_residual (
        .clk(clk), .nrst(nrst), .enable(residual_enable),
        .in_valid(residual_in_valid), .in_ready(residual_in_ready), .in_data(residual_in_data),
        .skip_valid(residual_skip_valid), .skip_ready(residual_skip_ready), .skip_data(residual_skip_data),
        .out_valid(residual_out_valid), .out_ready(residual_out_ready), .out_data(residual_out_data)
    );
    relu u_relu (
        .clk(clk), .nrst(nrst), .enable(relu_enable),
        .in_valid(relu_in_valid), .in_ready(relu_in_ready), .in_data(relu_in_data),
        .out_valid(relu_out_valid), .out_ready(relu_out_ready), .out_data(relu_out_data)
    );
    pooling u_pooling (
        .clk(clk), .nrst(nrst), .enable(pooling_enable), .iteration(pooling_iteration),
        .in_valid(pooling_in_valid), .in_ready(pooling_in_ready), .in_data(pooling_in_data),
        .out_valid(pooling_out_valid), .out_ready(pooling_out_ready), .out_data(pooling_out_data)
    );
    general_average_pooling u_gap (
        .clk(clk), .nrst(nrst), .enable(gap_enable), .iteration(gap_iteration),
        .in_valid(gap_in_valid), .in_ready(gap_in_ready), .in_data(gap_in_data),
        .out_valid(gap_out_valid), .out_ready(gap_out_ready), .out_data(gap_out_data)
    );

    // Arranged values and actual phase results remain available after each phase.
    reg signed [15:0] global_input [0:287];
    reg signed [15:0] global_kernel [0:67];
    reg signed [15:0] global_activation_schedule [0:2][0:1295];
    reg signed [15:0] global_kernel_schedule [0:2][0:1295];
    reg signed [15:0] global_skip_schedule [0:287];
    reg signed [15:0] global_phase_output [0:2][0:287];
    integer global_schedule_words [0:2];
    integer global_phase_received [0:2];
    reg signed [15:0] global_expected [0:287];
    real global_float_expected [0:71];
    real global_phase_snr [0:2];
    integer current_phase = 0;
    integer scoreboard_calls = 0;
    integer global_report_file = 0;
    integer cycle = 0;
    integer reset_index;
    reg controller_active = 0;
    reg [31:0] random_state = 32'h5eed1234;
    initial if ($value$plusargs("ready_seed=%d", random_state))
        $display("[ INFO ] ready seed=%0d", random_state);

    always @(negedge clk) begin
        if (!nrst) gap_out_ready = 0;
        else begin
            random_state = (random_state >> 1) ^ (32'hd0000001 & {32{random_state[0]}});
            gap_out_ready = (cycle % 19 >= 6) && random_state[0];
        end
    end

    // Only the final port is observed; there are no per-layer scoreboards.
    always @(posedge clk) begin
        if (!nrst) begin
            cycle <= 0;
            for (reset_index = 0; reset_index < 3; reset_index = reset_index + 1)
                global_phase_received[reset_index] <= 0;
        end else begin
            cycle <= cycle + 1;
            if (current_phase > 0 && gap_out_valid && gap_out_ready) begin
                global_phase_output[current_phase-1][global_phase_received[current_phase-1]] <= gap_out_data;
                global_phase_received[current_phase-1] <= global_phase_received[current_phase-1] + 1;
            end
        end
    end

    always @(negedge nrst) begin
        if (controller_active) disable controller;
        controller_active = 0;
        current_phase = 0;
        mac_in_valid = 0;
        residual_skip_valid = 0;
        mac_enable = 0; residual_enable = 0; relu_enable = 0;
        pooling_enable = 0; gap_enable = 0;
        if (global_report_file != 0) begin
            $fclose(global_report_file);
            global_report_file = 0;
        end
    end

    task automatic load_hex(input string path, input integer size);
        integer fd, n, j, status;
        string token;
        reg [7:0] digit;
        reg [15:0] value;
        begin
            fd = $fopen(path, "r");
            if (!fd) $fatal(1, "[ ERROR ] Cannot open reference file: %s", path);
            n = 0;
            while ($fscanf(fd, "%s", token) == 1) begin
                if (n >= size) $fatal(1, "[ ERROR ] Reference word count exceeds %0d: %s", size, path);
                if (token.len() != 4) $fatal(1, "[ ERROR ] Invalid reference word: %s in %s", token, path);
                for (j = 0; j < 4; j = j + 1) begin
                    digit = token[j];
                    if (!((digit >= "0" && digit <= "9") || (digit >= "a" && digit <= "f") ||
                          (digit >= "A" && digit <= "F")))
                        $fatal(1, "[ ERROR ] Invalid reference word: %s in %s", token, path);
                end
                status = $sscanf(token, "%h", value);
                if (status != 1) $fatal(1, "[ ERROR ] Invalid reference word in %s", path);
                global_expected[n] = value;
                n = n + 1;
            end
            $fclose(fd);
            if (n != size) $fatal(1, "[ ERROR ] Reference word count %0d, expected %0d: %s", n, size, path);
        end
    endtask

    task automatic load_float(input string path, input integer size);
        integer fd, n, status;
        string token, trailing;
        real value;
        begin
            fd = $fopen(path, "r");
            if (!fd) $fatal(1, "[ ERROR ] Cannot open float reference: %s", path);
            n = 0;
            while ($fscanf(fd, "%s", token) == 1) begin
                if (n >= size) $fatal(1, "[ ERROR ] Float reference count exceeds %0d: %s", size, path);
                status = $sscanf(token, "%f%s", value, trailing);
                if (status != 1) $fatal(1, "[ ERROR ] Invalid float reference: %s in %s", token, path);
                if (value != value || value > 1.0e300 || value < -1.0e300)
                    $fatal(1, "[ ERROR ] Invalid float reference: %s in %s", token, path);
                global_float_expected[n] = value;
                n = n + 1;
            end
            $fclose(fd);
            if (n != size) $fatal(1, "[ ERROR ] Float reference count %0d, expected %0d: %s", n, size, path);
        end
    endtask

    task automatic data_schedule(input integer phase);
        integer cin, cout, kernel_size, weight_base, output_words;
        integer output_index, y, x, oc, window, ky, kx, ic, iy, ix, term;
        reg signed [15:0] value;
        begin
            case (phase)
                1: begin cin = 8; cout = 2; kernel_size = 1; weight_base = 0; end
                2: begin cin = 2; cout = 2; kernel_size = 3; weight_base = 16; end
                3: begin cin = 2; cout = 8; kernel_size = 1; weight_base = 52; end
            endcase
            output_words = 36 * cout;
            global_schedule_words[phase-1] = output_words * kernel_size * kernel_size * cin;
            for (output_index = 0; output_index < output_words; output_index = output_index + 1) begin
                if (phase < 3) begin
                    oc = output_index % cout;
                    y = (output_index / cout) / 6;
                    x = (output_index / cout) % 6;
                end else begin
                    // c -> tile y,x -> dy,dx. Four consecutive outputs form one pool window.
                    oc = output_index / 36;
                    window = (output_index / 4) % 9;
                    y = (window / 3) * 2 + (output_index % 4) / 2;
                    x = (window % 3) * 2 + output_index % 2;
                    global_skip_schedule[output_index] = global_input[(y*6+x)*8+oc];
                end
                term = output_index * kernel_size * kernel_size * cin;
                for (ky = 0; ky < kernel_size; ky = ky + 1)
                    for (kx = 0; kx < kernel_size; kx = kx + 1)
                        for (ic = 0; ic < cin; ic = ic + 1) begin
                            iy = y + ky - kernel_size / 2;
                            ix = x + kx - kernel_size / 2;
                            value = 0;
                            if (iy >= 0 && iy < 6 && ix >= 0 && ix < 6) begin
                                if (phase == 1) value = global_input[(iy*6+ix)*cin+ic];
                                else value = global_phase_output[phase-2][(iy*6+ix)*cin+ic];
                            end
                            global_activation_schedule[phase-1][term] = value;
                            global_kernel_schedule[phase-1][term] = global_kernel[weight_base+((oc*kernel_size+ky)*kernel_size+kx)*cin+ic];
                            term = term + 1;
                        end
            end
        end
    endtask

    task automatic send_mac(input integer phase);
        integer i;
        begin
            for (i = 0; i < global_schedule_words[phase-1]; i = i + 1) begin
                @(negedge clk);
                mac_in_data = global_activation_schedule[phase-1][i];
                mac_kernel_data = global_kernel_schedule[phase-1][i];
                mac_in_valid = 1;
                @(posedge clk);
                while (!mac_in_ready) @(posedge clk);
                @(negedge clk);
                mac_in_valid = 0;
            end
        end
    endtask

    task automatic send_skip;
        integer i;
        begin
            for (i = 0; i < 288; i = i + 1) begin
                @(negedge clk);
                residual_skip_data = global_skip_schedule[i];
                residual_skip_valid = 1;
                @(posedge clk);
                while (!residual_skip_ready) @(posedge clk);
                @(negedge clk);
                residual_skip_valid = 0;
            end
        end
    endtask

    task automatic scoreboard(input integer phase);
        integer size, i, fd, actual_integer;
        string reference_name;
        real signal_power, noise_power, actual_real, difference, snr;
        begin
            case (phase)
                1: begin size = 72; reference_name = "ref_2_relu1"; end
                2: begin size = 72; reference_name = "ref_4_relu2"; end
                3: begin size = 8; reference_name = "ref_ouptut"; end
            endcase
            load_hex($sformatf("../data/%s.txt", reference_name), size);
            load_float($sformatf("../data/%s_float.txt", reference_name), size);
            fd = $fopen($sformatf("phase%0d_actual.txt", phase), "w");
            if (!fd) $fatal(1, "[ ERROR ] Cannot open phase output file");
            signal_power = 0.0; noise_power = 0.0;
            for (i = 0; i < size; i = i + 1) begin
                if (global_phase_output[phase-1][i] !== global_expected[i])
                    $fatal(1, "[ ERROR ] phase%0d index=%0d actual=%0d expected=%0d", phase, i,
                           $signed(global_phase_output[phase-1][i]), $signed(global_expected[i]));
                $fdisplay(fd, "%04h", global_phase_output[phase-1][i]);
                actual_integer = $signed(global_phase_output[phase-1][i]);
                actual_real = $itor(actual_integer) / 256.0;
                difference = global_float_expected[i] - actual_real;
                signal_power = signal_power + global_float_expected[i] * global_float_expected[i];
                noise_power = noise_power + difference * difference;
            end
            $fclose(fd);
            if (noise_power == 0.0) snr = 1.0e300;
            else if (signal_power == 0.0) snr = -1.0e300;
            else snr = 10.0 * $ln(signal_power / noise_power) / $ln(10.0);
            if (snr <= 30.0) $fatal(1, "[ ERROR ] phase%0d SNR=%f <= 30 dB", phase, snr);
            global_phase_snr[phase-1] = snr;
            scoreboard_calls = scoreboard_calls + 1;
            $fdisplay(global_report_file, "%0d %0d %.12f", phase, size, snr);
            $fflush(global_report_file);
            $display("[ PASS ] phase%0d (%0d values), SNR=%.8f dB", phase, size, snr);
        end
    endtask

    task automatic controller;
        integer phase, i, expected_words;
        begin : controller_run
            controller_active = 0;
            current_phase = 0;
            scoreboard_calls = 0;
            mac_in_valid = 0; residual_skip_valid = 0;
            nrst = 0;
            repeat (3) @(negedge clk);
            nrst = 1;
            controller_active = 1;
            load_hex("../data/ref_input.txt", 288);
            for (i = 0; i < 288; i = i + 1) global_input[i] = global_expected[i];
            load_hex("../data/ref_kernel.txt", 68);
            for (i = 0; i < 68; i = i + 1) global_kernel[i] = global_expected[i];
            global_report_file = $fopen("scoreboard_results.txt", "w");
            if (!global_report_file) $fatal(1, "[ ERROR ] Cannot open scoreboard report");
            for (phase = 1; phase <= 3; phase = phase + 1) begin
                @(negedge clk);
                current_phase = phase;
                mac_enable = 1; relu_enable = 1;
                residual_enable = phase == 3;
                pooling_enable = phase == 3;
                gap_enable = phase == 3;
                mac_iteration = phase == 1 ? 5'd8 : (phase == 2 ? 5'd18 : 5'd2);
                pooling_iteration = 5'd4; gap_iteration = 5'd9;
                expected_words = phase == 3 ? 8 : 72;
                data_schedule(phase);
                $display("[ INFO ] phase%0d scheduled %0d activation/kernel pairs", phase, global_schedule_words[phase-1]);
                fork
                    send_mac(phase);
                    begin if (phase == 3) send_skip(); end
                join
                @(negedge clk);
                while (global_phase_received[phase-1] < expected_words) @(negedge clk);
                wait (!(mac_out_valid || residual_out_valid || relu_out_valid || pooling_out_valid || gap_out_valid));
                if (global_phase_received[phase-1] != expected_words)
                    $fatal(1, "[ ERROR ] phase%0d output count mismatch", phase);
                scoreboard(phase);
            end
            $fclose(global_report_file);
            global_report_file = 0;
            controller_active = 0;
            $display("[ PASS ] ALL TESTS PASSED");
            $finish;
        end
    endtask

    initial controller();
endmodule
