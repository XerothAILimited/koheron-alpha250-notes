/*
 * axis_reset_sync.v
 * 
 * Purpose: Single-register reset synchronizer for local placement near 
 *          downstream modules to reduce routing delay.
 *
 * Used in snareSAR v1.8.0 to provide local reset synchronization for each
 * CIC IP core, reducing the routing distance from cfg_data[0] to internal
 * CIC reset registers.
 *
 * Author: snareSAR project
 * Version: 1.0
 * Date: 6 February 2026
 */

module axis_reset_sync (
    input  wire aclk,           // Clock input
    input  wire aresetn_in,     // Asynchronous reset input (active low)
    output wire aresetn_out     // Synchronized reset output (active low)
);

    /*
     * Single-stage synchronization register
     * 
     * Vivado will place this register near the downstream logic it drives,
     * reducing routing delay compared to driving resets directly from the
     * distant cfg_data source.
     *
     * Timing: Reset assertion/de-assertion delayed by 1 clock cycle.
     * This is acceptable because software holds resets for ≥10 cycles.
     */
    reg reset_sync_reg = 1'b0;
    
    always @(posedge aclk) begin
        reset_sync_reg <= aresetn_in;
    end
    
    // Output assignment
    assign aresetn_out = reset_sync_reg;

endmodule
