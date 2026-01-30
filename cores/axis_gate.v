// axis_gate.v - AXI-Stream Range Gating Module
// snareSAR Phase A/B
//
// Gates incoming sample stream based on delay and duration parameters
// CRITICAL: s_axis_tready is ALWAYS 1 - never backpressure upstream
// Includes internal FIFO to handle downstream backpressure

module axis_gate (
    input  wire        aclk,           // 250 MHz clock
    input  wire        aresetn,        // Active-low synchronous reset
    input  wire        prf_pulse,      // Start of new pulse (gate trigger)
    input  wire [15:0] gate_delay,     // Samples to skip after prf_pulse
    input  wire [15:0] gate_duration,  // Samples to capture

    // AXI-Stream slave (input from FIR)
    input  wire [63:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,  // ALWAYS 1

    // AXI-Stream master (output to header_insert)
    output reg  [63:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast    // Asserts on last sample of gate window
);

    // CRITICAL: Never backpressure upstream
    assign s_axis_tready = 1'b1;

    // State machine
    localparam IDLE    = 2'd0;
    localparam DELAY   = 2'd1;
    localparam CAPTURE = 2'd2;

    reg [1:0]  state;
    reg [15:0] delay_count;
    reg [15:0] sample_count;

    // Internal FIFO (64 entries deep) for backpressure handling
    localparam FIFO_DEPTH = 64;
    localparam FIFO_ADDR_WIDTH = 6;

    reg [63:0] fifo_mem [0:FIFO_DEPTH-1];
    reg        fifo_last_mem [0:FIFO_DEPTH-1];
    reg [FIFO_ADDR_WIDTH-1:0] fifo_wr_ptr;
    reg [FIFO_ADDR_WIDTH-1:0] fifo_rd_ptr;
    reg [FIFO_ADDR_WIDTH:0]   fifo_count;  // Extra bit for full detection

    wire fifo_empty = (fifo_count == 0);
    wire fifo_full  = (fifo_count == FIFO_DEPTH);

    // FIFO write - from capture state
    reg fifo_wr_en;
    reg [63:0] fifo_wr_data;
    reg fifo_wr_last;

    // FIFO read - to output
    wire fifo_rd_en = !fifo_empty && (!m_axis_tvalid || m_axis_tready);

    always @(posedge aclk) begin
        if (!aresetn) begin
            state        <= IDLE;
            delay_count  <= 16'd0;
            sample_count <= 16'd0;
            fifo_wr_ptr  <= 0;
            fifo_rd_ptr  <= 0;
            fifo_count   <= 0;
            fifo_wr_en   <= 1'b0;
            fifo_wr_data <= 64'd0;
            fifo_wr_last <= 1'b0;
            m_axis_tdata <= 64'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
        end else begin
            // Default
            fifo_wr_en <= 1'b0;

            // FIFO write
            if (fifo_wr_en && !fifo_full) begin
                fifo_mem[fifo_wr_ptr] <= fifo_wr_data;
                fifo_last_mem[fifo_wr_ptr] <= fifo_wr_last;
                fifo_wr_ptr <= fifo_wr_ptr + 1;
            end

            // FIFO read and output
            if (fifo_rd_en) begin
                m_axis_tdata  <= fifo_mem[fifo_rd_ptr];
                m_axis_tvalid <= 1'b1;
                m_axis_tlast  <= fifo_last_mem[fifo_rd_ptr];
                fifo_rd_ptr   <= fifo_rd_ptr + 1;
            end else if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;
            end

            // Update FIFO count
            if (fifo_wr_en && !fifo_full && fifo_rd_en) begin
                // Simultaneous read and write - count unchanged
            end else if (fifo_wr_en && !fifo_full) begin
                fifo_count <= fifo_count + 1;
            end else if (fifo_rd_en) begin
                fifo_count <= fifo_count - 1;
            end

            // State machine
            case (state)
                IDLE: begin
                    if (prf_pulse) begin
                        if (gate_duration == 0) begin
                            state <= IDLE;
                        end else if (gate_delay == 0) begin
                            state <= CAPTURE;
                            sample_count <= gate_duration;
                        end else begin
                            state <= DELAY;
                            delay_count <= gate_delay;
                        end
                    end
                end

                DELAY: begin
                    if (prf_pulse) begin
                        if (gate_duration == 0) begin
                            state <= IDLE;
                        end else if (gate_delay == 0) begin
                            state <= CAPTURE;
                            sample_count <= gate_duration;
                        end else begin
                            delay_count <= gate_delay;
                        end
                    end else if (s_axis_tvalid) begin
                        if (delay_count <= 1) begin
                            state <= CAPTURE;
                            sample_count <= gate_duration;
                        end else begin
                            delay_count <= delay_count - 1;
                        end
                    end
                end

                CAPTURE: begin
                    if (prf_pulse) begin
                        if (gate_duration == 0) begin
                            state <= IDLE;
                        end else if (gate_delay == 0) begin
                            sample_count <= gate_duration;
                        end else begin
                            state <= DELAY;
                            delay_count <= gate_delay;
                        end
                    end else if (s_axis_tvalid) begin
                        // Write to FIFO
                        fifo_wr_en   <= 1'b1;
                        fifo_wr_data <= s_axis_tdata;
                        fifo_wr_last <= (sample_count <= 1);

                        if (sample_count <= 1) begin
                            state <= IDLE;
                        end else begin
                            sample_count <= sample_count - 1;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
