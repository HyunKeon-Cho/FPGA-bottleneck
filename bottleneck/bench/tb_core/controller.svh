`ifndef CONTROLLER_SVH
`define CONTROLLER_SVH

    // ------------------------------------
    // core_reset
    // ------------------------------------
    task automatic core_reset;
        begin
            mac_in_enable       = 0;
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
                mac_in_enable   = 1;
                if (input_gap > 0) begin
                    @(negedge clk);
                    mac_in_enable = 0;
                    repeat (input_gap-1) @(negedge clk);
                end
            end
            @(negedge clk);
            mac_in_enable = 0;
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

            fork
                begin
                    send_mac(input_words);

                    @(negedge clk);
                    while (received < output_words) @(negedge clk);
                    wait (!(mac_out_enable || residual_out_enable || relu_out_enable || pooling_out_enable || gap_out_enable));
                    // All modules have a registered input and output stage.
                    // Drain the fixed latency even across bubbles between outputs.
                    repeat (12) @(negedge clk);
                    collecting = 0;
                end
                begin
                    while (collecting) begin
                        @(posedge clk);
                        if (collecting && gap_out_enable) begin
                            if (received >= output_words)
                                $fatal(1, "[ ERROR ] phase%0d extra output", phase);
                            output_data[received] = gap_out_data;
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
