// prf_timing.v - PRF Timing Generation Module
// snareSAR Phase A/B
// FIXED: 27 January 2026 - Always fire PRF at PPS to compensate for clock drift
//
// Generates PRF pulses at configurable rate with PPS synchronization
// Designed for 250 MHz FPGA clock, 2500 Hz default PRF

module prf_timing (
    input  wire        aclk,           // 250 MHz clock
    input  wire        aresetn,        // Active-low synchronous reset
    input  wire        prf_enable,     // Enable PRF generation
    input  wire        pps_pulse,      // PPS trigger from pps_sync
    input  wire [16:0] prf_divider,    // PRF period in clocks (default: 100000)
    input  wire [11:0] trigger_width,  // TXDATA pulse width in clocks
    output reg         prf_pulse,      // Single-cycle PRF pulse
    output reg  [31:0] prf_count,      // Running PRF counter
    output reg  [31:0] pps_count,      // Running PPS counter
    output reg  [31:0] prf_at_pps,     // PRF count latched at last PPS
    output reg         txdata_out      // Chirp trigger output
);

    // Internal divider counter
    reg [16:0] divider_count;

    // Pre-computed threshold for timing closure (FIX: 28 Jan 2026)
    // Breaks critical path: (prf_divider - 1) computed one cycle early
    // Reduces logic levels from 9 to ~6
    reg [16:0] prf_threshold;

    // TXDATA pulse width counter
    reg [11:0] txdata_count;

    always @(posedge aclk) begin
        if (!aresetn) begin
            divider_count <= 17'd0;
            prf_threshold <= 17'd99999;  // Default: 100000 - 1
            prf_pulse     <= 1'b0;
            prf_count     <= 32'd0;
            pps_count     <= 32'd0;
            prf_at_pps    <= 32'd0;
            txdata_out    <= 1'b0;
            txdata_count  <= 12'd0;
        end else begin
            // Default: clear single-cycle pulse
            prf_pulse <= 1'b0;

            // Update threshold register (breaks critical path)
            prf_threshold <= prf_divider - 1;

            // PPS handling - increment PPS counter
            if (pps_pulse) begin
                pps_count <= pps_count + 1;
            end

            if (prf_enable) begin
                // PPS resets the divider for phase synchronization
                if (pps_pulse) begin
                    // FIXED: Always fire PRF at PPS to compensate for clock drift
                    // This ensures exactly 2500 PRFs per GPS second regardless of
                    // FPGA clock frequency tolerance
                    prf_pulse     <= 1'b1;
                    prf_count     <= prf_count + 1;
                    prf_at_pps    <= prf_count + 1;  // Latch incremented value
                    // Start TXDATA pulse
                    if (trigger_width > 0) begin
                        txdata_out   <= 1'b1;
                        txdata_count <= trigger_width - 1;
                    end
                    // Reset divider for phase synchronization
                    divider_count <= 17'd0;
                end else if (divider_count >= prf_threshold) begin
                    // PRF pulse on divider rollover (normal case)
                    divider_count <= 17'd0;
                    prf_pulse     <= 1'b1;
                    prf_count     <= prf_count + 1;

                    // Start TXDATA pulse
                    if (trigger_width > 0) begin
                        txdata_out   <= 1'b1;
                        txdata_count <= trigger_width - 1;
                    end
                end else begin
                    divider_count <= divider_count + 1;
                end

                // TXDATA pulse width management
                if (txdata_out && txdata_count > 0) begin
                    txdata_count <= txdata_count - 1;
                end else if (txdata_out && txdata_count == 0) begin
                    txdata_out <= 1'b0;
                end
            end else begin
                // Disabled: hold outputs low, hold counters
                txdata_out <= 1'b0;
                // Still latch prf_at_pps on PPS when disabled
                if (pps_pulse) begin
                    prf_at_pps <= prf_count;
                end
            end
        end
    end

endmodule
