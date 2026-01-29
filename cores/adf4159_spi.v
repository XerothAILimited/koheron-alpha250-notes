// adf4159_spi.v - ADF4159 SPI Interface Module
// snareSAR Phase A/B
//
// SPI master for ADF4159 PLL configuration
// Clock: 250 MHz / 16 = 15.625 MHz SPI clock

module adf4159_spi (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        spi_start,      // Start SPI transaction (1 cycle)
    input  wire [31:0] spi_data,       // Data to send (MSB first)
    output reg         spi_busy,       // Transaction in progress
    output reg         spi_done,       // Transaction complete (1 cycle)
    output reg         ce_out,         // Chip enable (active high)
    output reg         clk_out,        // SPI clock
    output reg         data_out,       // SPI data (directly to pin)
    output reg         le_out,         // Latch enable
    input  wire        muxout_in       // Lock detect input
);

    // Clock divider: 250MHz / 16 = 15.625MHz
    // We need 8 system clocks per SPI clock half-period
    localparam CLK_DIV = 8;

    // State machine
    localparam IDLE       = 3'd0;
    localparam CE_SETUP   = 3'd1;
    localparam DATA_TX    = 3'd2;
    localparam LE_PULSE   = 3'd3;
    localparam CE_HOLD    = 3'd4;

    reg [2:0]  state;
    reg [31:0] shift_reg;
    reg [5:0]  bit_count;      // 0-31 for 32 bits
    reg [3:0]  clk_div_count;  // Clock divider counter
    reg [4:0]  setup_count;    // CE setup / LE pulse / CE hold counter

    always @(posedge aclk) begin
        if (!aresetn) begin
            state         <= IDLE;
            shift_reg     <= 32'd0;
            bit_count     <= 6'd0;
            clk_div_count <= 4'd0;
            setup_count   <= 5'd0;
            spi_busy      <= 1'b0;
            spi_done      <= 1'b0;
            ce_out        <= 1'b0;
            clk_out       <= 1'b0;
            data_out      <= 1'b0;
            le_out        <= 1'b0;
        end else begin
            // Default: clear single-cycle done signal
            spi_done <= 1'b0;

            case (state)
                IDLE: begin
                    clk_out  <= 1'b0;
                    le_out   <= 1'b0;
                    ce_out   <= 1'b0;
                    data_out <= 1'b0;

                    if (spi_start) begin
                        shift_reg     <= spi_data;
                        spi_busy      <= 1'b1;
                        state         <= CE_SETUP;
                        setup_count   <= 5'd0;
                        ce_out        <= 1'b1;
                        // Pre-load first bit MSB
                        data_out      <= spi_data[31];
                    end
                end

                CE_SETUP: begin
                    // Wait 2 SPI clock periods (32 system clocks) before data
                    if (setup_count >= (2 * CLK_DIV * 2 - 1)) begin
                        state         <= DATA_TX;
                        bit_count     <= 6'd0;
                        clk_div_count <= 4'd0;
                        clk_out       <= 1'b0;
                    end else begin
                        setup_count <= setup_count + 1;
                    end
                end

                DATA_TX: begin
                    // Generate SPI clock and shift data
                    if (clk_div_count >= (CLK_DIV - 1)) begin
                        clk_div_count <= 4'd0;
                        clk_out <= ~clk_out;

                        // On falling edge of SPI clock, shift to next bit
                        if (clk_out) begin
                            if (bit_count >= 31) begin
                                // All bits transmitted
                                state       <= LE_PULSE;
                                setup_count <= 5'd0;
                                clk_out     <= 1'b0;
                            end else begin
                                bit_count <= bit_count + 1;
                                data_out  <= shift_reg[30 - bit_count];
                            end
                        end
                    end else begin
                        clk_div_count <= clk_div_count + 1;
                    end
                end

                LE_PULSE: begin
                    // LE high for 2 SPI clock periods
                    le_out <= 1'b1;
                    if (setup_count >= (2 * CLK_DIV * 2 - 1)) begin
                        state       <= CE_HOLD;
                        setup_count <= 5'd0;
                        le_out      <= 1'b0;
                    end else begin
                        setup_count <= setup_count + 1;
                    end
                end

                CE_HOLD: begin
                    // CE hold for 2 SPI clock periods after LE falls
                    if (setup_count >= (2 * CLK_DIV * 2 - 1)) begin
                        state    <= IDLE;
                        ce_out   <= 1'b0;
                        spi_busy <= 1'b0;
                        spi_done <= 1'b1;
                    end else begin
                        setup_count <= setup_count + 1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
