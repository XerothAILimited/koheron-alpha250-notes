// header_insert.v - Packet Header Insertion Module
// snareSAR Phase A/B
//
// Inserts 16-byte header (2 x 64-bit words) before each packet
// Header format:
//   Word 0: {prf_count[31:0], magic[31:0]}  magic = 0x534E4152 ('SNAR')
//   Word 1: {flags[7:0], pol[7:0], n_samples[15:0], pps_count[31:0]}

module header_insert (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        prf_pulse,      // Capture timing values
    input  wire [31:0] prf_count,      // From prf_timing
    input  wire [31:0] pps_count,      // From prf_timing
    input  wire [15:0] n_samples,      // Sample count (100 or 250)
    input  wire        pol,            // Current polarization
    input  wire [7:0]  flags,          // Mode flags

    // AXI-Stream slave (from axis_gate)
    input  wire [63:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output reg         s_axis_tready,
    input  wire        s_axis_tlast,

    // AXI-Stream master (to packetizer)
    output reg  [63:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast
);

    // Magic value
    localparam [31:0] MAGIC = 32'h534E4152;  // 'SNAR' ASCII

    // State machine
    localparam IDLE    = 2'd0;
    localparam HEADER0 = 2'd1;
    localparam HEADER1 = 2'd2;
    localparam DATA    = 2'd3;

    reg [1:0] state;

    // Latched values at prf_pulse
    reg [31:0] latched_prf_count;
    reg [31:0] latched_pps_count;
    reg        latched_pol;

    // Header words
    wire [63:0] header_word0;
    wire [63:0] header_word1;

    assign header_word0 = {latched_prf_count, MAGIC};
    assign header_word1 = {flags, {7'b0, latched_pol}, n_samples, latched_pps_count};

    always @(posedge aclk) begin
        if (!aresetn) begin
            state              <= IDLE;
            latched_prf_count  <= 32'd0;
            latched_pps_count  <= 32'd0;
            latched_pol        <= 1'b0;
            s_axis_tready      <= 1'b0;
            m_axis_tdata       <= 64'd0;
            m_axis_tvalid      <= 1'b0;
            m_axis_tlast       <= 1'b0;
        end else begin
            // Latch values on prf_pulse (even during other states)
            if (prf_pulse) begin
                latched_prf_count <= prf_count;
                latched_pps_count <= pps_count;
                latched_pol       <= pol;
            end

            case (state)
                IDLE: begin
                    s_axis_tready <= 1'b0;
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;

                    // Wait for data to arrive (indicates gate captured data)
                    if (s_axis_tvalid) begin
                        state <= HEADER0;
                    end
                end

                HEADER0: begin
                    s_axis_tready <= 1'b0;
                    m_axis_tdata  <= header_word0;
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast  <= 1'b0;

                    if (m_axis_tready) begin
                        state <= HEADER1;
                    end
                end

                HEADER1: begin
                    s_axis_tready <= 1'b0;
                    m_axis_tdata  <= header_word1;
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast  <= 1'b0;

                    if (m_axis_tready) begin
                        state         <= DATA;
                        s_axis_tready <= 1'b1;
                    end
                end

                DATA: begin
                    s_axis_tready <= m_axis_tready;

                    if (s_axis_tvalid && s_axis_tready) begin
                        m_axis_tdata  <= s_axis_tdata;
                        m_axis_tvalid <= 1'b1;
                        m_axis_tlast  <= s_axis_tlast;

                        if (s_axis_tlast) begin
                            state <= IDLE;
                        end
                    end else if (m_axis_tready) begin
                        m_axis_tvalid <= 1'b0;
                        m_axis_tlast  <= 1'b0;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
