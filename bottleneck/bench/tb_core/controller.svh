`ifndef CONTROLLER_SVH
`define CONTROLLER_SVH

    // ------------------------------------
    // core_reset
    // ------------------------------------
    task automatic core_reset;
        begin
            mac_in_valid        = 0;
            residual_skip_valid = 0;
            mac_enable          = 0;
            residual_enable     = 0;
            relu_enable         = 0;
            pooling_enable      = 0;
            gap_enable          = 0;

            nrst = 0;
            repeat (3) @(negedge clk);
            nrst = 1;
        end
    endtask

    // ------------------------------------
    // send_mac
    // ------------------------------------
    task automatic send_mac(
        input integer       words
    );
        integer             i;

        begin
            for (i = 0; i < words; i = i + 1) begin
                @(negedge clk);
                mac_in_data     = feature_buf[i];
                mac_kernel_data = kernel_buf[i];
                mac_in_valid    = 1;

                @(posedge clk);
                while (!mac_in_ready) @(posedge clk);

                @(negedge clk);
                mac_in_valid = 0;
            end
        end
    endtask

    // ------------------------------------
    // send_skip
    // ------------------------------------
    task automatic send_skip;
        integer             i;

        begin
            for (i = 0; i < INPUT_WORDS; i = i + 1) begin
                @(negedge clk);
                residual_skip_data  = skip_buf[i];
                residual_skip_valid = 1;

                @(posedge clk);
                while (!residual_skip_ready) @(posedge clk);

                @(negedge clk);
                residual_skip_valid = 0;
            end
        end
    endtask

    // ------------------------------------
    // core_run
    // ------------------------------------
    task automatic core_run(
        input integer       phase,
        input integer       input_words,
        input integer       output_words
    );
        integer             received;
        reg                 collecting;

        begin
            received   = 0;
            collecting = 1;
            //$display("[ INFO ] phase%0d scheduled %0d activation/kernel pairs", phase, input_words);

            fork
                begin
                    fork
                        send_mac(input_words);
                        begin
                            if (phase == 3) send_skip();
                        end
                    join

                    @(negedge clk);
                    while (received < output_words) @(negedge clk);
                    wait (!(mac_out_valid || residual_out_valid || relu_out_valid || pooling_out_valid || gap_out_valid));
                    collecting = 0;
                end
                begin
                    while (collecting) begin
                        @(posedge clk);
                        if (collecting && output_valid && output_ready) begin
                            output_data[received] = output_word;
                            received              = received + 1;
                        end
                    end
                end
            join

            if (received != output_words)
                $fatal(1, "[ ERROR ] phase%0d output count mismatch", phase);
        end
    endtask


`endif // CONTROLLER_SVH
