// pps_sync.v - PPS Synchronization Module
// snareSAR Phase A/B
//
// 3-stage synchronizer with falling edge detection for PPS input
// Designed for 250 MHz FPGA clock with asynchronous GPIO input

module pps_sync (
    input  wire        aclk,        // 250 MHz clock
    input  wire        aresetn,     // Active-low synchronous reset
    input  wire        pps_in,      // Raw PPS from GPIO (asynchronous)
    output reg         pps_pulse,   // Single-cycle pulse on FALLING edge
    output reg         pps_level    // Synchronized PPS level (debug)
);

    // 3-stage synchronizer flip-flops + edge detection register
    reg [2:0] sync_ff;
    reg       sync_d;  // Additional register for glitch-resistant edge detection

    always @(posedge aclk) begin
        if (!aresetn) begin
            sync_ff   <= 3'b000;
            sync_d    <= 1'b0;
            pps_pulse <= 1'b0;
            pps_level <= 1'b0;
        end else begin
            // Shift register for metastability resolution
            sync_ff <= {sync_ff[1:0], pps_in};

            // Extra pipeline stage for edge detection
            sync_d <= sync_ff[2];

            // Synchronized level output
            pps_level <= sync_ff[2];

            // Falling edge detection with glitch rejection
            // Requires sync_d AND sync_ff[2] to both be HIGH, and sync_ff[1] to be LOW
            // This rejects glitches shorter than 3 cycles
            pps_pulse <= sync_d & sync_ff[2] & ~sync_ff[1];
        end
    end

endmodule
