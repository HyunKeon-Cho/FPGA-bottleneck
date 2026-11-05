`ifndef RESNET_SVH
`define RESNET_SVH

    // ------------------------------------
    // Model Dimensions
    // ------------------------------------
    localparam integer  PHASE_COUNT = 3;
    localparam integer  INPUT_WORDS = 288;
    localparam integer  KERNEL_WORDS = 68;
    localparam integer  PHASE_FEATURE_WORDS = 72;
    localparam integer  OUTPUT_WORDS = 8;
    localparam integer  PHASE1_SCHEDULE_WORDS = 576;
    localparam integer  PHASE2_SCHEDULE_WORDS = 1296;
    localparam integer  PHASE3_SCHEDULE_WORDS = 576;

    localparam integer  BUFFER_SIZE = 1296; // max size

    // ------------------------------------
    // Quantization Scale
    // ------------------------------------
    localparam real     Q_SCALE = 2.0 ** FRAC_WIDTH;

`endif // RESNET_SVH
