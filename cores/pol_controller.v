// pol_controller.v - Polarization Control Module
// snareSAR Phase A/B
//
// Controls RF switch for polarization selection
// Supports manual mode and auto-toggle mode

module pol_controller (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        prf_pulse,      // From prf_timing
    input  wire        pol_auto,       // Auto-toggle enable
    input  wire        pol_manual,     // Manual polarization value
    output reg         pol_gpio,       // RF switch control (0=V, 1=H)
    output wire        current_pol     // Current polarization for status
);

    // Internal toggle register for auto mode
    reg pol_state;

    // Current polarization output
    assign current_pol = pol_gpio;

    always @(posedge aclk) begin
        if (!aresetn) begin
            pol_state <= 1'b0;  // Start with V-pol
            pol_gpio  <= 1'b0;
        end else begin
            // Auto mode: toggle on PRF pulse
            if (pol_auto && prf_pulse) begin
                pol_state <= ~pol_state;
            end

            // Output selection
            if (pol_auto) begin
                pol_gpio <= pol_state;
            end else begin
                pol_gpio <= pol_manual;
            end
        end
    end

endmodule
