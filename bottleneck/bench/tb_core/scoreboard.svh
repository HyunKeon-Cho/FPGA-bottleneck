`ifndef SCOREBOARD_SVH
`define SCOREBOARD_SVH

    // ------------------------------------
    // Scoreboard State
    // ------------------------------------
    // Phase-boundary checking only; actual output capture is in core_run().
    real                global_phase_snr [0:PHASE_COUNT-1];
    integer             scoreboard_calls = 0;
    integer             global_report_file = 0;

    // ------------------------------------
    // scoreboard_init
    // ------------------------------------
    task automatic scoreboard_init;
        begin
            scoreboard_calls = 0;
            global_report_file = $fopen("scoreboard_results.txt", "w");
            if (!global_report_file) $fatal(1, "[ ERROR ] Cannot open scoreboard report");
        end
    endtask

    // ------------------------------------
    // scoreboard
    // ------------------------------------
    task automatic scoreboard(
        input reg signed [BITWIDTH-1:0] actual_buf [0:BUFFER_SIZE-1],
        input integer                   size,
        input string                    reference_name
    );
        integer                   phase;
        integer                   i;
        integer                   fd;
        integer                   actual_integer;
        real                      signal_power;
        real                      noise_power;
        real                      actual_real;
        real                      difference;
        real                      snr;
        reg signed [BITWIDTH-1:0] actual_value;

        begin
            // Call order supplies report numbering; references come from the caller.
            phase = scoreboard_calls + 1;

            load_hex($sformatf("../data/%s.txt", reference_name), size);
            load_float($sformatf("../data/%s_float.txt", reference_name), size);

            fd = $fopen($sformatf("phase%0d_actual.txt", phase), "w");
            if (!fd) $fatal(1, "[ ERROR ] Cannot open phase output file");

            signal_power = 0.0;
            noise_power  = 0.0;

            for (i = 0; i < size; i = i + 1) begin
                actual_value = actual_buf[i];

                if (actual_value !== global_expected[i])
                    $fatal(1, "[ ERROR ] phase%0d index=%0d actual=%0d expected=%0d", phase, i,
                           $signed(actual_value), $signed(global_expected[i]));

                $fdisplay(fd, "%04h", actual_value);
                actual_integer = $signed(actual_value);
                actual_real    = $itor(actual_integer) / Q_SCALE;
                difference     = global_float_expected[i] - actual_real;
                signal_power   = signal_power + global_float_expected[i] * global_float_expected[i];
                noise_power    = noise_power + difference * difference;
            end

            $fclose(fd);

            if (noise_power == 0.0) snr = 1.0e300;
            else if (signal_power == 0.0) snr = -1.0e300;
            else snr = 10.0 * $ln(signal_power / noise_power) / $ln(10.0);

            if (snr <= 30.0) $fatal(1, "[ ERROR ] phase%0d SNR=%f <= 30 dB", phase, snr);

            global_phase_snr[phase-1] = snr;
            scoreboard_calls          = scoreboard_calls + 1;

            $fdisplay(global_report_file, "%0d %0d %.12f", phase, size, snr);
            $fflush(global_report_file);
            $display("[ PASS ] phase%0d (%0d values), SNR=%.8f dB", phase, size, snr);
        end
    endtask

    // ------------------------------------
    // scoreboard_finish
    // ------------------------------------
    task automatic scoreboard_finish;
        begin
            $fclose(global_report_file);
            global_report_file = 0;
            if (scoreboard_calls != PHASE_COUNT)
                $fatal(1, "[ ERROR ] Expected %0d scoreboard calls, got %0d", PHASE_COUNT, scoreboard_calls);
            $display("[ PASS ] ALL TESTS PASSED");
        end
    endtask

`endif // SCOREBOARD_SVH
