`ifndef UTILES_SVH
`define UTILES_SVH

    // ------------------------------------
    // File Loader Buffers
    // ------------------------------------
    // File-loader scratch buffers, also used for original input/kernel loading.
    reg signed [BITWIDTH-1:0] global_expected [0:INPUT_WORDS-1];
    real                      global_float_expected [0:PHASE_FEATURE_WORDS-1];

    // ------------------------------------
    // load_hex
    // ------------------------------------
    task automatic load_hex(
        input string        path,
        input integer       size
    );
        integer             fd;
        integer             n;
        integer             j;
        integer             status;
        string              token;
        reg [7:0]           digit;
        reg [BITWIDTH-1:0]  value;

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
                n                  = n + 1;
            end

            $fclose(fd);
            if (n != size) $fatal(1, "[ ERROR ] Reference word count %0d, expected %0d: %s", n, size, path);
        end
    endtask

    // ------------------------------------
    // load_float
    // ------------------------------------
    task automatic load_float(
        input string        path,
        input integer       size
    );
        integer             fd;
        integer             n;
        integer             status;
        string              token;
        string              trailing;
        real                value;

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
                n                        = n + 1;
            end

            $fclose(fd);
            if (n != size) $fatal(1, "[ ERROR ] Float reference count %0d, expected %0d: %s", n, size, path);
        end
    endtask

    // ------------------------------------
    // load_data
    // ------------------------------------
    task automatic load_data;
        integer             i;

        begin
            load_hex("../data/ref_input.txt", INPUT_WORDS);
            for (i = 0; i < INPUT_WORDS; i = i + 1)
                feature[i] = global_expected[i];

            load_hex("../data/ref_kernel.txt", KERNEL_WORDS);
            for (i = 0; i < KERNEL_WORDS; i = i + 1)
                kernel[i] = global_expected[i];
        end
    endtask

`endif // UTILES_SVH
