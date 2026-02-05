`timescale 1 ns / 1 ps

module spi_init_200mhz
(
  // System signals
  input  wire        clk,
  input  wire        aresetn,

  // SPI outputs
  output wire        spi_sclk,
  output wire        spi_mosi,
  output wire        spi_ss0_n,
  output wire        spi_ss1_n,
  output wire        spi_ss2_n,

  // Status output
  output wire        init_done
);

  // State encoding
  localparam [3:0]
    ST_RESET     = 4'd0,
    ST_IDLE      = 4'd1,
    ST_LMK_LOAD  = 4'd2,
    ST_LMK_SEND  = 4'd3,
    ST_LMK_WAIT  = 4'd4,
    ST_ADC0_LOAD = 4'd5,
    ST_ADC0_SEND = 4'd6,
    ST_ADC0_WAIT = 4'd7,
    ST_ADC1_LOAD = 4'd8,
    ST_ADC1_SEND = 4'd9,
    ST_ADC1_WAIT = 4'd10,
    ST_DONE      = 4'd11;

  // Timing parameters at 200 MHz (5 ns period)
  // SPI clock: 200 MHz / 20 = 10 MHz (100 ns period)
  localparam [4:0] CLK_DIV = 5'd10;  // Half period = 10 cycles = 50 ns

  // Inter-command delay: 200 cycles = 1 us
  localparam [11:0] CMD_DELAY = 12'd200;

  // Post-reset delay for LMK04906: 2000 cycles = 10 us
  localparam [11:0] RESET_DELAY = 12'd2000;

  // Number of commands
  localparam [4:0] LMK_CMD_COUNT = 5'd25;
  localparam [1:0] ADC_CMD_COUNT = 2'd3;

  // Registers
  reg [3:0] int_state_reg, int_state_next;
  reg [31:0] int_shift_reg, int_shift_next;
  reg [5:0] int_bit_cnt_reg, int_bit_cnt_next;
  reg [4:0] int_cmd_idx_reg, int_cmd_idx_next;
  reg [4:0] int_clk_cnt_reg, int_clk_cnt_next;
  reg [11:0] int_delay_cnt_reg, int_delay_cnt_next;
  reg int_sclk_reg, int_sclk_next;
  reg int_mosi_reg, int_mosi_next;
  reg int_ss0_reg, int_ss0_next;
  reg int_ss1_reg, int_ss1_next;
  reg int_ss2_reg, int_ss2_next;
  reg int_done_reg, int_done_next;

  // ===========================================================================
  // LMK04906 Configuration for 200 MHz Output
  // ===========================================================================
  // VCO Target:     2400 MHz (LMK04906 VCO range: 2370-2600 MHz)
  // Reference:      25 MHz (Alpha250 TCXO)
  // PLL2_N:         96 (25 MHz × 96 = 2400 MHz)
  // CLKout_DIV:     12 (2400 MHz / 12 = 200 MHz)
  //
  // Register changes from 225 MHz configuration:
  //   R1:  CLKout1_DIV  11 -> 12  (0x00000161 -> 0x00000181)
  //   R3:  CLKout3_DIV  11 -> 12  (0x00000163 -> 0x00000183)
  //   R29: PLL2_N_CAL   99 -> 96  (0x01000C7D -> 0x01000C01)
  //   R30: PLL2_N       99 -> 96  (0x05000C7E -> 0x05000C02)
  // ===========================================================================

  // LMK04906 configuration data (25 commands, 32 bits each)
  // Format: Bits [31:5] = data, Bits [4:0] = register address
  reg [31:0] lmk_rom [0:24];
  initial begin
    lmk_rom[0]  = 32'h00020000;  // R0: RESET=1
    lmk_rom[1]  = 32'h00001F40;  // R0: Config with RESET=0
    lmk_rom[2]  = 32'h00000181;  // R1: CLKout1_DIV=12 (200MHz)
    lmk_rom[3]  = 32'h00000142;  // R2
    lmk_rom[4]  = 32'h00000183;  // R3: CLKout3_DIV=12 (200MHz)
    lmk_rom[5]  = 32'h80001F44;  // R4
    lmk_rom[6]  = 32'h80001F45;  // R5
    lmk_rom[7]  = 32'h01800006;  // R6: CLKout0
    lmk_rom[8]  = 32'h01100007;  // R7: CLKout1
    lmk_rom[9]  = 32'h01010008;  // R8: CLKout2
    lmk_rom[10] = 32'h55555549;  // R9: CLKout dividers
    lmk_rom[11] = 32'h1801420A;  // R10: OSCin
    lmk_rom[12] = 32'h0401100B;  // R11: PLL1
    lmk_rom[13] = 32'h1B0C018C;  // R12: PLL1
    lmk_rom[14] = 32'h230324ED;  // R13: PLL2
    lmk_rom[15] = 32'h9200000E;  // R14: PLL2
    lmk_rom[16] = 32'h8000020F;  // R15
    lmk_rom[17] = 32'h01550410;  // R16
    lmk_rom[18] = 32'h000000D8;  // R24
    lmk_rom[19] = 32'h01010019;  // R25
    lmk_rom[20] = 32'hAFA8001A;  // R26: PLL2_DLD
    lmk_rom[21] = 32'h1800005B;  // R27
    lmk_rom[22] = 32'h0080029C;  // R28: PLL2_R=8 (unchanged)
    lmk_rom[23] = 32'h01000C01;  // R29: PLL2_N_CAL=96 (200MHz)
    lmk_rom[24] = 32'h05000C02;  // R30: PLL2_N=96 (200MHz), triggers VCO cal
  end

  // LTC2157 ADC configuration data (3 commands, 16 bits each)
  // Format: Bits [15:8] = address, Bits [7:0] = data
  reg [15:0] adc_rom [0:2];
  initial begin
    adc_rom[0] = 16'h0080;  // Soft reset
    adc_rom[1] = 16'h031E;  // Output format
    adc_rom[2] = 16'h0401;  // Mode config
  end

  // Sequential logic
  always @(posedge clk)
  begin
    if(~aresetn)
    begin
      int_state_reg <= ST_RESET;
      int_shift_reg <= 32'd0;
      int_bit_cnt_reg <= 6'd0;
      int_cmd_idx_reg <= 5'd0;
      int_clk_cnt_reg <= 5'd0;
      int_delay_cnt_reg <= 12'd0;
      int_sclk_reg <= 1'b0;
      int_mosi_reg <= 1'b0;
      int_ss0_reg <= 1'b1;
      int_ss1_reg <= 1'b1;
      int_ss2_reg <= 1'b1;
      int_done_reg <= 1'b0;
    end
    else
    begin
      int_state_reg <= int_state_next;
      int_shift_reg <= int_shift_next;
      int_bit_cnt_reg <= int_bit_cnt_next;
      int_cmd_idx_reg <= int_cmd_idx_next;
      int_clk_cnt_reg <= int_clk_cnt_next;
      int_delay_cnt_reg <= int_delay_cnt_next;
      int_sclk_reg <= int_sclk_next;
      int_mosi_reg <= int_mosi_next;
      int_ss0_reg <= int_ss0_next;
      int_ss1_reg <= int_ss1_next;
      int_ss2_reg <= int_ss2_next;
      int_done_reg <= int_done_next;
    end
  end

  // Combinational next-state logic
  always @*
  begin
    // Default: hold current values
    int_state_next = int_state_reg;
    int_shift_next = int_shift_reg;
    int_bit_cnt_next = int_bit_cnt_reg;
    int_cmd_idx_next = int_cmd_idx_reg;
    int_clk_cnt_next = int_clk_cnt_reg;
    int_delay_cnt_next = int_delay_cnt_reg;
    int_sclk_next = int_sclk_reg;
    int_mosi_next = int_mosi_reg;
    int_ss0_next = int_ss0_reg;
    int_ss1_next = int_ss1_reg;
    int_ss2_next = int_ss2_reg;
    int_done_next = int_done_reg;

    case(int_state_reg)

      ST_RESET:
      begin
        // Wait a few cycles after reset release
        int_delay_cnt_next = int_delay_cnt_reg + 1'b1;
        if(int_delay_cnt_reg == 12'd100)
        begin
          int_delay_cnt_next = 12'd0;
          int_state_next = ST_IDLE;
        end
      end

      ST_IDLE:
      begin
        // Start LMK04906 initialization
        int_cmd_idx_next = 5'd0;
        int_state_next = ST_LMK_LOAD;
      end

      ST_LMK_LOAD:
      begin
        // Load next LMK command into shift register
        int_shift_next = lmk_rom[int_cmd_idx_reg];
        int_bit_cnt_next = 6'd32;
        int_clk_cnt_next = 5'd0;
        int_ss0_next = 1'b0;  // Assert CS (active low)
        int_mosi_next = lmk_rom[int_cmd_idx_reg][31];  // First bit ready
        int_state_next = ST_LMK_SEND;
      end

      ST_LMK_SEND:
      begin
        // SPI clock generation and data shifting
        int_clk_cnt_next = int_clk_cnt_reg + 1'b1;

        if(int_clk_cnt_reg == CLK_DIV - 1'b1)
        begin
          // Rising edge of SPI clock - data is sampled by slave here
          int_sclk_next = 1'b1;
        end
        else if(int_clk_cnt_reg == {CLK_DIV, 1'b0} - 1'b1)
        begin
          // Falling edge of SPI clock
          int_sclk_next = 1'b0;
          int_clk_cnt_next = 5'd0;

          // Shift data and update MOSI
          int_shift_next = {int_shift_reg[30:0], 1'b0};
          int_bit_cnt_next = int_bit_cnt_reg - 1'b1;

          if(int_bit_cnt_reg == 6'd1)
          begin
            // Last bit sent, deassert CS
            int_ss0_next = 1'b1;  // Rising edge latches data in LMK04906
            int_mosi_next = 1'b0;
            int_delay_cnt_next = 12'd0;
            int_state_next = ST_LMK_WAIT;
          end
          else
          begin
            // Next bit
            int_mosi_next = int_shift_reg[30];
          end
        end
      end

      ST_LMK_WAIT:
      begin
        // Inter-command delay
        int_delay_cnt_next = int_delay_cnt_reg + 1'b1;

        // Use longer delay after reset command (index 0)
        if((int_cmd_idx_reg == 5'd0 && int_delay_cnt_reg == RESET_DELAY - 1'b1) ||
           (int_cmd_idx_reg != 5'd0 && int_delay_cnt_reg == CMD_DELAY - 1'b1))
        begin
          int_delay_cnt_next = 12'd0;
          int_cmd_idx_next = int_cmd_idx_reg + 1'b1;

          if(int_cmd_idx_reg == LMK_CMD_COUNT - 1'b1)
          begin
            // LMK done, start ADC0
            int_cmd_idx_next = 5'd0;
            int_ss0_next = 1'b0;  // Return LEuWire to low per datasheet
            int_state_next = ST_ADC0_LOAD;
          end
          else
          begin
            int_state_next = ST_LMK_LOAD;
          end
        end
      end

      ST_ADC0_LOAD:
      begin
        // Load next ADC command into shift register (16-bit)
        int_shift_next = {adc_rom[int_cmd_idx_reg[1:0]], 16'd0};
        int_bit_cnt_next = 6'd16;
        int_clk_cnt_next = 5'd0;
        int_ss1_next = 1'b0;  // Assert ADC0 CS
        int_mosi_next = adc_rom[int_cmd_idx_reg[1:0]][15];
        int_state_next = ST_ADC0_SEND;
      end

      ST_ADC0_SEND:
      begin
        // SPI clock generation for ADC0
        int_clk_cnt_next = int_clk_cnt_reg + 1'b1;

        if(int_clk_cnt_reg == CLK_DIV - 1'b1)
        begin
          int_sclk_next = 1'b1;
        end
        else if(int_clk_cnt_reg == {CLK_DIV, 1'b0} - 1'b1)
        begin
          int_sclk_next = 1'b0;
          int_clk_cnt_next = 5'd0;

          int_shift_next = {int_shift_reg[30:0], 1'b0};
          int_bit_cnt_next = int_bit_cnt_reg - 1'b1;

          if(int_bit_cnt_reg == 6'd1)
          begin
            int_ss1_next = 1'b1;  // Deassert ADC0 CS
            int_mosi_next = 1'b0;
            int_delay_cnt_next = 12'd0;
            int_state_next = ST_ADC0_WAIT;
          end
          else
          begin
            int_mosi_next = int_shift_reg[30];
          end
        end
      end

      ST_ADC0_WAIT:
      begin
        int_delay_cnt_next = int_delay_cnt_reg + 1'b1;

        if(int_delay_cnt_reg == CMD_DELAY - 1'b1)
        begin
          int_delay_cnt_next = 12'd0;
          int_cmd_idx_next = int_cmd_idx_reg + 1'b1;

          if(int_cmd_idx_reg[1:0] == ADC_CMD_COUNT - 1'b1)
          begin
            // ADC0 done, start ADC1
            int_cmd_idx_next = 5'd0;
            int_state_next = ST_ADC1_LOAD;
          end
          else
          begin
            int_state_next = ST_ADC0_LOAD;
          end
        end
      end

      ST_ADC1_LOAD:
      begin
        // Load next ADC command for ADC1
        int_shift_next = {adc_rom[int_cmd_idx_reg[1:0]], 16'd0};
        int_bit_cnt_next = 6'd16;
        int_clk_cnt_next = 5'd0;
        int_ss2_next = 1'b0;  // Assert ADC1 CS
        int_mosi_next = adc_rom[int_cmd_idx_reg[1:0]][15];
        int_state_next = ST_ADC1_SEND;
      end

      ST_ADC1_SEND:
      begin
        // SPI clock generation for ADC1
        int_clk_cnt_next = int_clk_cnt_reg + 1'b1;

        if(int_clk_cnt_reg == CLK_DIV - 1'b1)
        begin
          int_sclk_next = 1'b1;
        end
        else if(int_clk_cnt_reg == {CLK_DIV, 1'b0} - 1'b1)
        begin
          int_sclk_next = 1'b0;
          int_clk_cnt_next = 5'd0;

          int_shift_next = {int_shift_reg[30:0], 1'b0};
          int_bit_cnt_next = int_bit_cnt_reg - 1'b1;

          if(int_bit_cnt_reg == 6'd1)
          begin
            int_ss2_next = 1'b1;  // Deassert ADC1 CS
            int_mosi_next = 1'b0;
            int_delay_cnt_next = 12'd0;
            int_state_next = ST_ADC1_WAIT;
          end
          else
          begin
            int_mosi_next = int_shift_reg[30];
          end
        end
      end

      ST_ADC1_WAIT:
      begin
        int_delay_cnt_next = int_delay_cnt_reg + 1'b1;

        if(int_delay_cnt_reg == CMD_DELAY - 1'b1)
        begin
          int_delay_cnt_next = 12'd0;
          int_cmd_idx_next = int_cmd_idx_reg + 1'b1;

          if(int_cmd_idx_reg[1:0] == ADC_CMD_COUNT - 1'b1)
          begin
            // All done
            int_state_next = ST_DONE;
          end
          else
          begin
            int_state_next = ST_ADC1_LOAD;
          end
        end
      end

      ST_DONE:
      begin
        // Initialization complete, set final signal states
        int_done_next = 1'b1;
        int_sclk_next = 1'b0;
        int_mosi_next = 1'b0;
        int_ss0_next = 1'b0;   // LMK04906 LEuWire returned to low per datasheet
        int_ss1_next = 1'b1;   // ADC0 CS idle high (standard SPI)
        int_ss2_next = 1'b1;   // ADC1 CS idle high (standard SPI)
      end

      default:
      begin
        int_state_next = ST_RESET;
      end

    endcase
  end

  // Output assignments
  assign spi_sclk  = int_sclk_reg;
  assign spi_mosi  = int_mosi_reg;
  assign spi_ss0_n = int_ss0_reg;
  assign spi_ss1_n = int_ss1_reg;
  assign spi_ss2_n = int_ss2_reg;
  assign init_done = int_done_reg;

endmodule
