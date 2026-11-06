`timescale 1ns/1ps

module tb_core;

    // ------------------------------------
    // Data Configuration
    // ------------------------------------
    // Reference vectors and behavioral DUT arithmetic are fixed to signed Q7.8.
    localparam integer  BITWIDTH = 16;
    localparam integer  INT_WIDTH = 7;
    localparam integer  FRAC_WIDTH = BITWIDTH - 1 - INT_WIDTH;

    // ------------------------------------
    // Clock and Reset
    // ------------------------------------
    reg                 clk = 0;
    reg                 nrst = 0;

    always #5 clk = ~clk;

    // ------------------------------------
    // MAC
    // ------------------------------------
    reg                        mac_enable = 0;
    reg [4:0]                  mac_iteration = 1;
    reg                        mac_in_valid = 0;
    wire                       mac_in_ready;
    reg signed [BITWIDTH-1:0]  mac_in_data = 0;
    reg signed [BITWIDTH-1:0]  mac_kernel_data = 0;
    wire                       mac_out_valid;
    wire                       mac_out_ready;
    wire signed [BITWIDTH-1:0] mac_out_data;

    mac #(
        .BITWIDTH (BITWIDTH)
    ) u_mac (
        .clk         (clk),
        .nrst        (nrst),
        .enable      (mac_enable),
        .iteration   (mac_iteration),
        .in_valid    (mac_in_valid),
        .in_ready    (mac_in_ready),
        .in_data     (mac_in_data),
        .kernel_data (mac_kernel_data),
        .out_valid   (mac_out_valid),
        .out_ready   (mac_out_ready),
        .out_data    (mac_out_data)
    );

    // ------------------------------------
    // Residual
    // ------------------------------------
    reg                        residual_enable = 0;
    wire                       residual_in_valid;
    wire                       residual_in_ready;
    wire signed [BITWIDTH-1:0] residual_in_data;
    reg                        residual_skip_valid = 0;
    wire                       residual_skip_ready;
    reg signed [BITWIDTH-1:0]  residual_skip_data = 0;
    wire                       residual_out_valid;
    wire                       residual_out_ready;
    wire signed [BITWIDTH-1:0] residual_out_data;

    residual #(
        .BITWIDTH (BITWIDTH)
    ) u_residual (
        .clk        (clk),
        .nrst       (nrst),
        .enable     (residual_enable),
        .in_valid   (residual_in_valid),
        .in_ready   (residual_in_ready),
        .in_data    (residual_in_data),
        .skip_valid (residual_skip_valid),
        .skip_ready (residual_skip_ready),
        .skip_data  (residual_skip_data),
        .out_valid  (residual_out_valid),
        .out_ready  (residual_out_ready),
        .out_data   (residual_out_data)
    );

    // ------------------------------------
    // ReLU
    // ------------------------------------
    reg                        relu_enable = 0;
    wire                       relu_in_valid;
    wire                       relu_in_ready;
    wire signed [BITWIDTH-1:0] relu_in_data;
    wire                       relu_out_valid;
    wire                       relu_out_ready;
    wire signed [BITWIDTH-1:0] relu_out_data;

    relu #(
        .BITWIDTH (BITWIDTH)
    ) u_relu (
        .clk       (clk),
        .nrst      (nrst),
        .enable    (relu_enable),
        .in_valid  (relu_in_valid),
        .in_ready  (relu_in_ready),
        .in_data   (relu_in_data),
        .out_valid (relu_out_valid),
        .out_ready (relu_out_ready),
        .out_data  (relu_out_data)
    );

    // ------------------------------------
    // Pooling
    // ------------------------------------
    reg                        pooling_enable    = 0;
    reg [4:0]                  pooling_iteration = 4;
    wire                       pooling_in_valid;
    wire                       pooling_in_ready;
    wire signed [BITWIDTH-1:0] pooling_in_data;
    wire                       pooling_out_valid;
    wire                       pooling_out_ready;
    wire signed [BITWIDTH-1:0] pooling_out_data;

    pooling #(
        .BITWIDTH (BITWIDTH)
    ) u_pooling (
        .clk       (clk),
        .nrst      (nrst),
        .enable    (pooling_enable),
        .iteration (pooling_iteration),
        .in_valid  (pooling_in_valid),
        .in_ready  (pooling_in_ready),
        .in_data   (pooling_in_data),
        .out_valid (pooling_out_valid),
        .out_ready (pooling_out_ready),
        .out_data  (pooling_out_data)
    );

    // ------------------------------------
    // GAP
    // ------------------------------------
    reg                        gap_enable    = 0;
    reg [4:0]                  gap_iteration = 9;
    wire                       gap_in_valid;
    wire                       gap_in_ready;
    wire signed [BITWIDTH-1:0] gap_in_data;
    wire                       gap_out_valid;
    wire                       gap_out_ready;
    wire signed [BITWIDTH-1:0] gap_out_data;

    general_average_pooling #(
        .BITWIDTH (BITWIDTH)
    ) u_gap (
        .clk       (clk),
        .nrst      (nrst),
        .enable    (gap_enable),
        .iteration (gap_iteration),
        .in_valid  (gap_in_valid),
        .in_ready  (gap_in_ready),
        .in_data   (gap_in_data),
        .out_valid (gap_out_valid),
        .out_ready (gap_out_ready),
        .out_data  (gap_out_data)
    );

    // ------------------------------------
    // Pipeline Connections
    // ------------------------------------
    assign mac_out_ready      = residual_in_ready;

    assign residual_in_valid  = mac_out_valid;
    assign residual_out_ready = relu_in_ready;
    assign residual_in_data   = mac_out_data;

    assign relu_in_valid      = residual_out_valid;
    assign relu_out_ready     = pooling_in_ready;
    assign relu_in_data       = residual_out_data;

    assign pooling_in_valid   = relu_out_valid;
    assign pooling_out_ready  = gap_in_ready;
    assign pooling_in_data    = relu_out_data;

    assign gap_in_valid       = pooling_out_valid;
    assign gap_in_data        = pooling_out_data;

    // ------------------------------------
    // Model Configuration
    // ------------------------------------
    `include "ResNet.svh"

    // ------------------------------------
    // Data buffers
    // ------------------------------------
    reg signed [BITWIDTH-1:0] feature [0:BUFFER_SIZE-1];
    reg signed [BITWIDTH-1:0] kernel  [0:BUFFER_SIZE-1];

    // ------------------------------------
    // Shared Buffers
    // ------------------------------------
    reg signed [BITWIDTH-1:0] feature_buf [0:BUFFER_SIZE-1];
    reg signed [BITWIDTH-1:0] kernel_buf  [0:BUFFER_SIZE-1];
    reg signed [BITWIDTH-1:0] skip_buf    [0:BUFFER_SIZE-1];
    reg signed [BITWIDTH-1:0] output_data [0:BUFFER_SIZE-1];

    // ------------------------------------
    // Core Output Interface
    // ------------------------------------
    wire                       output_valid;
    reg                        output_ready = 0;
    wire signed [BITWIDTH-1:0] output_word;

    assign output_valid  = gap_out_valid;
    assign output_word   = gap_out_data;
    assign gap_out_ready = output_ready;

    // ------------------------------------
    // TB Tasks
    // ------------------------------------
    `include "PS.svh"
    `include "utiles.svh"
    `include "scoreboard.svh"
    `include "controller.svh"

    // ------------------------------------
    // Simulation
    // ------------------------------------
    initial begin : simulation_run
        load_data();
        core_reset();
        scoreboard_init();

        phase1_data_schedule(feature, kernel, feature_buf, kernel_buf);
        phase1_setup();
        core_run(1, PHASE1_SCHEDULE_WORDS, PHASE_FEATURE_WORDS);
        scoreboard(output_data, PHASE_FEATURE_WORDS, "ref_2_relu1");

        phase2_data_schedule(output_data, kernel, feature_buf, kernel_buf);
        phase2_setup();
        core_run(2, PHASE2_SCHEDULE_WORDS, PHASE_FEATURE_WORDS);
        scoreboard(output_data, PHASE_FEATURE_WORDS, "ref_4_relu2");

        phase3_data_schedule(output_data, kernel, feature, feature_buf, kernel_buf, skip_buf);
        phase3_setup();
        core_run(3, PHASE3_SCHEDULE_WORDS, OUTPUT_WORDS);
        scoreboard(output_data, OUTPUT_WORDS, "ref_ouptut");

        $finish;
    end
endmodule
