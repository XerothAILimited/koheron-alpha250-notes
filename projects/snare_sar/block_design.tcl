# ==============================================================================
# snareSAR FPGA Block Design -- v1.8.0
#
# v1.6.0 changes:
#   - Master clock reduced from 225 MHz to 200 MHz for timing margin
#   - LMK04906 VCO: 2475 MHz -> 2400 MHz (PLL2_N: 99 -> 96)
#   - CLKout_DIV: 11 -> 12
#   - Post-CIC rate: 56.25 Msps -> 50 Msps
#   - Post-FIR rate: 28.125 Msps -> 25 Msps
#   - Range per sample: 5.333 m -> 6.0 m
#
# v1.5.0 changes (retained):
#
# Changes from v1.4.0:
#   C1  ADF4159 SPI control via CFG registers (spi_data, spi_start)
#   C2  Configurable n_samples (replaces const_n_samples)
#   C3  Configurable flags (replaces const_flags)
#   C4  STS expanded to 160 bits (current_pol, pps_level)
#   C5  Packetizer CONTINUOUS = TRUE for streaming
#   C6  CFG_DATA_WIDTH 160->224, STS_DATA_WIDTH 128->160
#   C7  ADF4159 spi_busy routed to STS[130] for software polling
#
# CFG bit layout (224 bits = 7 words):
#   [0]         pipeline_aresetn     (existing)
#   [1]         pktzr_aresetn        (existing)
#   [2]         writer_aresetn       (existing)
#   [31:3]      (reserved)           (existing)
#   [63:32]     min_addr             (existing)
#   [95:64]     packet_size          (existing)
#   [96]        prf_enable           (existing)
#   [113:97]    prf_divider          (existing)
#   [125:114]   trigger_width        (existing)
#   [126]       pol_auto             (existing)
#   [127]       pol_manual           (existing)
#   [143:128]   gate_delay           (existing)
#   [159:144]   gate_duration        (existing)
#   [191:160]   adf_spi_data         (NEW -- C1, Word 5)
#   [192]       adf_spi_start        (NEW -- C1, Word 6 bit 0)
#   [199:193]   (reserved)           (NEW -- write zero)
#   [207:200]   flags                (NEW -- C3, Word 6 bits 15:8)
#   [223:208]   n_samples            (NEW -- C2, Word 6 bits 31:16)
#
# STS bit layout (160 bits = 5 words):
#   [15:0]      writer_addr          (existing)
#   [31:16]     (reserved)           (existing)
#   [63:32]     prf_count            (existing)
#   [95:64]     pps_count            (existing)
#   [127:96]    prf_at_pps           (existing)
#   [128]       current_pol          (NEW -- C4, Word 4 bit 0)
#   [129]       pps_level            (NEW -- C4, Word 4 bit 1)
#   [130]       spi_busy             (NEW -- C7, Word 4 bit 2)
#   [159:131]   (reserved)           (NEW -- reads zero)
# ==============================================================================

# ==============================================================================
# snareSAR GPIO Port Override
# Remove the default exp_p/exp_n bidirectional ports and create specific ports
# ==============================================================================

# Delete default expansion connector ports (created by cfg/ports.tcl)
delete_bd_objs [get_bd_ports exp_n]
delete_bd_objs [get_bd_ports exp_p]

# Create snareSAR-specific GPIO ports
# Inputs (directly to FPGA from external hardware)
create_bd_port -dir I pps_in
create_bd_port -dir I muxout_in

# Outputs (directly from FPGA to external hardware)
create_bd_port -dir O adf_ce
create_bd_port -dir O adf_clk
create_bd_port -dir O adf_data
create_bd_port -dir O adf_le
create_bd_port -dir O pol_gpio
create_bd_port -dir O txdata_out

# ==============================================================================

# Create clk_wiz
cell xilinx.com:ip:clk_wiz pll_0 {
  PRIMITIVE PLL
  PRIM_IN_FREQ.VALUE_SRC USER
  PRIM_IN_FREQ 200.0
  PRIM_SOURCE Differential_clock_capable_pin
  CLKOUT1_USED true
  CLKOUT1_REQUESTED_OUT_FREQ 200.0
  CLKOUT1_REQUESTED_PHASE 78.75
  USE_RESET false
} {
  clk_in1_n adc_1_clk_n
  clk_in1_p adc_1_clk_p
}

# Create xlconstant
cell xilinx.com:ip:xlconstant const_0

# Create processing_system7
# NOTE: SPI0 EMIO connections removed - spi_init module handles Configuration SPI
# SPI1 retained for Precision ADC (separate from Configuration SPI)
cell xilinx.com:ip:processing_system7 ps_0 {
  PCW_IMPORT_BOARD_PRESET cfg/koheron_alpha250.xml
  PCW_USE_S_AXI_ACP 1
  PCW_USE_DEFAULT_ACP_USER_VAL 1
} {
  M_AXI_GP0_ACLK pll_0/clk_out1
  S_AXI_ACP_ACLK pll_0/clk_out1
  SPI1_SCLK_O spi_adc_sclk
  SPI1_MOSI_O spi_adc_mosi
  SPI1_MISO_I spi_adc_miso
  SPI1_SS_I const_0/dout
  SPI1_SS_O spi_adc_ss
}

# Create all required interconnections
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {
  make_external {FIXED_IO, DDR}
  Master Disable
  Slave Disable
} [get_bd_cells ps_0]

# Create spi_init - automatic SPI initialization for LMK04906 and ADCs
# Uses FCLK_CLK0 (200 MHz from PS) which is always available at power-up
# Runs before Linux boots, eliminating chicken-and-egg clock initialization problem
cell pavel-demin:user:spi_init_200mhz spi_init_0 {} {
  clk ps_0/FCLK_CLK0
  aresetn ps_0/FCLK_RESET0_N
  spi_sclk spi_cfg_sclk
  spi_mosi spi_cfg_mosi
  spi_ss0_n spi_cfg_ss
  spi_ss1_n spi_cfg_ss1
  spi_ss2_n spi_cfg_ss2
}

# Note: spi_cfg_miso input port is left unconnected (spi_init is write-only)
# Note: spi_init_0/init_done output is left unconnected (v1.6.0 will route via CDC)

# Create proc_sys_reset
cell xilinx.com:ip:proc_sys_reset rst_0 {} {
  ext_reset_in const_0/dout
  dcm_locked pll_0/locked
  slowest_sync_clk pll_0/clk_out1
}

# ADC

for {set i 0} {$i <= 3} {incr i} {

  # Create axis_adc
  cell pavel-demin:user:axis_adc adc_$i {
    ADC_DATA_WIDTH 14
    AXIS_TDATA_WIDTH 16
  } {
    adc_n adc_${i}_n
    adc_p adc_${i}_p
    aclk pll_0/clk_out1
  }

}

# HUB

# Create axi_hub
# v1.5.0 C6: CFG_DATA_WIDTH 160->224 (new fields for C1, C2, C3)
# v1.5.0 C6: STS_DATA_WIDTH 128->160 (new fields for C4, C7)
cell pavel-demin:user:axi_hub hub_0 {
  CFG_DATA_WIDTH 224
  STS_DATA_WIDTH 160
} {
  S_AXI ps_0/M_AXI_GP0
  aclk pll_0/clk_out1
  aresetn rst_0/peripheral_aresetn
}

# Create port_slicer
cell pavel-demin:user:port_slicer slice_0 {
  DIN_WIDTH 224 DIN_FROM 0 DIN_TO 0
} {
  din hub_0/cfg_data
}

# Create port_slicer
cell pavel-demin:user:port_slicer slice_1 {
  DIN_WIDTH 224 DIN_FROM 1 DIN_TO 1
} {
  din hub_0/cfg_data
}

# Create port_slicer
cell pavel-demin:user:port_slicer slice_2 {
  DIN_WIDTH 224 DIN_FROM 2 DIN_TO 2
} {
  din hub_0/cfg_data
}

# ==============================================================================
# v1.8.0 Local Reset Synchronizers
# Reduces routing delay by placing sync registers near downstream modules
# ==============================================================================

# Reset synchronizers for CIC filters
cell pavel-demin:user:axis_reset_sync reset_sync_cic0 {} {
  aclk pll_0/clk_out1
  aresetn_in slice_0/dout
}

cell pavel-demin:user:axis_reset_sync reset_sync_cic1 {} {
  aclk pll_0/clk_out1
  aresetn_in slice_0/dout
}

cell pavel-demin:user:axis_reset_sync reset_sync_cic2 {} {
  aclk pll_0/clk_out1
  aresetn_in slice_0/dout
}

cell pavel-demin:user:axis_reset_sync reset_sync_cic3 {} {
  aclk pll_0/clk_out1
  aresetn_in slice_0/dout
}

# Reset synchronizers for FIR chain
cell pavel-demin:user:axis_reset_sync reset_sync_comb {} {
  aclk pll_0/clk_out1
  aresetn_in slice_0/dout
}

cell pavel-demin:user:axis_reset_sync reset_sync_fir {} {
  aclk pll_0/clk_out1
  aresetn_in slice_0/dout
}

cell pavel-demin:user:axis_reset_sync reset_sync_subset {} {
  aclk pll_0/clk_out1
  aresetn_in slice_0/dout
}

# Create port_slicer
cell pavel-demin:user:port_slicer slice_3 {
  DIN_WIDTH 224 DIN_FROM 63 DIN_TO 32
} {
  din hub_0/cfg_data
}

# Create port_slicer
cell pavel-demin:user:port_slicer slice_4 {
  DIN_WIDTH 224 DIN_FROM 95 DIN_TO 64
} {
  din hub_0/cfg_data
}

# snareSAR Configuration Port Slicers

# prf_enable: cfg_data[96]
cell pavel-demin:user:port_slicer slice_prf_enable {
  DIN_WIDTH 224 DIN_FROM 96 DIN_TO 96
} {
  din hub_0/cfg_data
}

# prf_divider: cfg_data[113:97]
cell pavel-demin:user:port_slicer slice_prf_divider {
  DIN_WIDTH 224 DIN_FROM 113 DIN_TO 97
} {
  din hub_0/cfg_data
}

# trigger_width: cfg_data[125:114]
cell pavel-demin:user:port_slicer slice_trigger_width {
  DIN_WIDTH 224 DIN_FROM 125 DIN_TO 114
} {
  din hub_0/cfg_data
}

# pol_auto: cfg_data[126]
cell pavel-demin:user:port_slicer slice_pol_auto {
  DIN_WIDTH 224 DIN_FROM 126 DIN_TO 126
} {
  din hub_0/cfg_data
}

# pol_manual: cfg_data[127]
cell pavel-demin:user:port_slicer slice_pol_manual {
  DIN_WIDTH 224 DIN_FROM 127 DIN_TO 127
} {
  din hub_0/cfg_data
}

# gate_delay: cfg_data[143:128]
cell pavel-demin:user:port_slicer slice_gate_delay {
  DIN_WIDTH 224 DIN_FROM 143 DIN_TO 128
} {
  din hub_0/cfg_data
}

# gate_duration: cfg_data[159:144]
cell pavel-demin:user:port_slicer slice_gate_duration {
  DIN_WIDTH 224 DIN_FROM 159 DIN_TO 144
} {
  din hub_0/cfg_data
}

# ==============================================================================
# v1.5.0 New Configuration Port Slicers (C1, C2, C3)
# ==============================================================================

# adf_spi_data: cfg_data[191:160] -- ADF4159 32-bit register value (C1, Word 5)
cell pavel-demin:user:port_slicer slice_adf_spi_data {
  DIN_WIDTH 224 DIN_FROM 191 DIN_TO 160
} {
  din hub_0/cfg_data
}

# adf_spi_start: cfg_data[192] -- ADF4159 SPI transaction trigger (C1, Word 6 bit 0)
cell pavel-demin:user:port_slicer slice_adf_spi_start {
  DIN_WIDTH 224 DIN_FROM 192 DIN_TO 192
} {
  din hub_0/cfg_data
}

# flags: cfg_data[207:200] -- header flags field (C3, Word 6 bits 15:8)
cell pavel-demin:user:port_slicer slice_flags {
  DIN_WIDTH 224 DIN_FROM 207 DIN_TO 200
} {
  din hub_0/cfg_data
}

# n_samples: cfg_data[223:208] -- header n_samples field (C2, Word 6 bits 31:16)
cell pavel-demin:user:port_slicer slice_n_samples {
  DIN_WIDTH 224 DIN_FROM 223 DIN_TO 208
} {
  din hub_0/cfg_data
}

# CIC

for {set i 0} {$i <= 3} {incr i} {

  # Create cic_compiler
  cell xilinx.com:ip:cic_compiler cic_$i  {
    INPUT_DATA_WIDTH.VALUE_SRC USER
    FILTER_TYPE Decimation
    NUMBER_OF_STAGES 6
    FIXED_OR_INITIAL_RATE 4
    INPUT_SAMPLE_FREQUENCY 200
    CLOCK_FREQUENCY 200
    INPUT_DATA_WIDTH 14
    QUANTIZATION Truncation
    OUTPUT_DATA_WIDTH 24
    USE_XTREME_DSP_SLICE false
    HAS_ARESETN true
  } {
    S_AXIS_DATA adc_$i/M_AXIS
    aclk pll_0/clk_out1
    aresetn reset_sync_cic$i/aresetn_out
  }

}

# FIR

# Create axis_combiner
cell  xilinx.com:ip:axis_combiner comb_0 {
  TDATA_NUM_BYTES.VALUE_SRC USER
  TDATA_NUM_BYTES 3
  NUM_SI 4
} {
  S00_AXIS cic_0/M_AXIS_DATA
  S01_AXIS cic_1/M_AXIS_DATA
  S02_AXIS cic_2/M_AXIS_DATA
  S03_AXIS cic_3/M_AXIS_DATA
  aclk pll_0/clk_out1
  aresetn reset_sync_comb/aresetn_out
}

# Create fir_compiler
cell xilinx.com:ip:fir_compiler fir_0 {
  DATA_WIDTH.VALUE_SRC USER
  DATA_WIDTH 24
  COEFFICIENTVECTOR {-4.3206471974e-08, 1.9581108834e-08, 3.8109090962e-08, 1.4084131418e-09, 1.2186120186e-08, -4.3002365521e-08, -1.3853077565e-07, 1.0133745579e-07, 3.7888894052e-07, -1.6394613230e-07, -7.7661761489e-07, 2.0712149544e-07, 1.3774224210e-06, -1.9384365527e-07, -2.2249377290e-06, 7.2763377227e-08, 3.3549988889e-06, 2.2117927620e-07, -4.7889010594e-06, -7.6397724595e-07, 6.5260611238e-06, 1.6368965465e-06, -8.5375061091e-06, -2.9191987685e-06, 1.0758341788e-05, 4.6752496998e-06, -1.3084991486e-05, -6.9412383420e-06, 1.5373724961e-05, 9.7084647273e-06, -1.7443962288e-05, -1.2905490830e-05, 1.9086646276e-05, 1.6380162505e-05, -2.0078608383e-05, -1.9883422927e-05, 2.0203022903e-05, 2.3056727953e-05, -1.9275907764e-05, -2.5425425753e-05, 1.7177613167e-05, 2.6400053739e-05, -1.3887984508e-05, -2.5287767236e-05, 9.5223982251e-06, 2.1313177486e-05, -4.3728197481e-06, -1.3665196308e-05, -1.0766754409e-06, 1.5310917825e-06, 6.1157778312e-06, 1.5831781930e-05, -9.8065695691e-06, -3.9025740577e-05, 1.0994139826e-05, 6.8433254890e-05, -8.3394585095e-06, -1.0413520871e-04, 3.7650515294e-07, 1.4583183818e-04, 1.4403443484e-05, -1.9277411182e-04, -3.7440682291e-05, 2.4371243539e-04, 6.9969543240e-05, -2.9687173927e-04, -1.1285857228e-04, 3.4996062912e-04, 1.6643173499e-04, -4.0023458429e-04, -2.3031764274e-04, 4.4453252714e-04, 3.0318466104e-04, -4.7951215941e-04, -3.8264756455e-04, 5.0179308310e-04, 4.6508817914e-04, -5.0822117940e-04, -5.4554763871e-04, 4.9616951008e-04, 6.1766717590e-04, -4.6388070868e-04, -6.7369245331e-04, 4.1083915738e-04, 7.0454923950e-04, -3.3816268708e-04, -6.9999979578e-04, 2.4899722791e-04, 6.4888144112e-04, -1.4890118284e-04, -5.3942758146e-04, 4.6206061884e-05, 3.5965967563e-04, 4.7605082323e-05, -9.8021126546e-05, -1.1791553911e-04, -2.5647044402e-04, 1.4635687092e-04, 7.1327754530e-04, -1.1093829736e-04, -1.2799048805e-03, -1.4106495666e-05, 1.9613024094e-03, 2.5839388583e-04, -2.7593013177e-03, -6.5548048055e-04, 3.6720962046e-03, 1.2430372921e-03, -4.6937909542e-03, -2.0632159584e-03, 5.8140101675e-03, 3.1633610776e-03, -7.0175713933e-03, -4.5973156063e-03, 8.2841916600e-03, 6.4277320980e-03, -9.5881685667e-03, -8.7303353142e-03, 1.0896800128e-02, 1.1598799243e-02, -1.2171477770e-02, -1.5158439259e-02, 1.3362938210e-02, 1.9583979076e-02, -1.4406996028e-02, -2.5135038845e-02, 1.5213119554e-02, 3.2223155290e-02, -1.5638192699e-02, -4.1549149361e-02, 1.5420585824e-02, 5.4413218064e-02, -1.3991942256e-02, -7.3511311682e-02, 9.8306147091e-03, 1.0538098831e-01, 2.4767895457e-03, -1.7013983793e-01, -5.3519295197e-02, 3.5729875325e-01, 5.9530013734e-01, 3.5729875325e-01, -5.3519295197e-02, -1.7013983793e-01, 2.4767895457e-03, 1.0538098831e-01, 9.8306147091e-03, -7.3511311682e-02, -1.3991942256e-02, 5.4413218064e-02, 1.5420585824e-02, -4.1549149361e-02, -1.5638192699e-02, 3.2223155290e-02, 1.5213119554e-02, -2.5135038845e-02, -1.4406996028e-02, 1.9583979076e-02, 1.3362938210e-02, -1.5158439259e-02, -1.2171477770e-02, 1.1598799243e-02, 1.0896800128e-02, -8.7303353142e-03, -9.5881685667e-03, 6.4277320980e-03, 8.2841916600e-03, -4.5973156063e-03, -7.0175713933e-03, 3.1633610776e-03, 5.8140101675e-03, -2.0632159584e-03, -4.6937909542e-03, 1.2430372921e-03, 3.6720962046e-03, -6.5548048055e-04, -2.7593013177e-03, 2.5839388583e-04, 1.9613024094e-03, -1.4106495666e-05, -1.2799048805e-03, -1.1093829736e-04, 7.1327754530e-04, 1.4635687092e-04, -2.5647044402e-04, -1.1791553911e-04, -9.8021126546e-05, 4.7605082323e-05, 3.5965967563e-04, 4.6206061884e-05, -5.3942758146e-04, -1.4890118284e-04, 6.4888144112e-04, 2.4899722791e-04, -6.9999979578e-04, -3.3816268708e-04, 7.0454923950e-04, 4.1083915738e-04, -6.7369245331e-04, -4.6388070868e-04, 6.1766717590e-04, 4.9616951008e-04, -5.4554763871e-04, -5.0822117940e-04, 4.6508817914e-04, 5.0179308310e-04, -3.8264756455e-04, -4.7951215941e-04, 3.0318466104e-04, 4.4453252714e-04, -2.3031764274e-04, -4.0023458429e-04, 1.6643173499e-04, 3.4996062912e-04, -1.1285857228e-04, -2.9687173927e-04, 6.9969543240e-05, 2.4371243539e-04, -3.7440682291e-05, -1.9277411182e-04, 1.4403443484e-05, 1.4583183818e-04, 3.7650515294e-07, -1.0413520871e-04, -8.3394585095e-06, 6.8433254890e-05, 1.0994139826e-05, -3.9025740577e-05, -9.8065695691e-06, 1.5831781930e-05, 6.1157778312e-06, 1.5310917825e-06, -1.0766754409e-06, -1.3665196308e-05, -4.3728197481e-06, 2.1313177486e-05, 9.5223982251e-06, -2.5287767236e-05, -1.3887984508e-05, 2.6400053739e-05, 1.7177613167e-05, -2.5425425753e-05, -1.9275907764e-05, 2.3056727953e-05, 2.0203022903e-05, -1.9883422927e-05, -2.0078608383e-05, 1.6380162505e-05, 1.9086646276e-05, -1.2905490830e-05, -1.7443962288e-05, 9.7084647273e-06, 1.5373724961e-05, -6.9412383420e-06, -1.3084991486e-05, 4.6752496998e-06, 1.0758341788e-05, -2.9191987685e-06, -8.5375061091e-06, 1.6368965465e-06, 6.5260611238e-06, -7.6397724595e-07, -4.7889010594e-06, 2.2117927620e-07, 3.3549988889e-06, 7.2763377227e-08, -2.2249377290e-06, -1.9384365527e-07, 1.3774224210e-06, 2.0712149544e-07, -7.7661761489e-07, -1.6394613230e-07, 3.7888894052e-07, 1.0133745579e-07, -1.3853077565e-07, -4.3002365521e-08, 1.2186120186e-08, 1.4084131418e-09, 3.8109090962e-08, 1.9581108834e-08, -4.3206471974e-08}
  COEFFICIENT_WIDTH 24
  QUANTIZATION Quantize_Only
  BESTPRECISION true
  FILTER_TYPE Decimation
  DECIMATION_RATE 2
  NUMBER_CHANNELS 1
  NUMBER_PATHS 2
  SAMPLE_FREQUENCY 50
  CLOCK_FREQUENCY 200
  OUTPUT_ROUNDING_MODE Convergent_Rounding_to_Even
  OUTPUT_WIDTH 18
  M_DATA_HAS_TREADY true
  HAS_ARESETN true
} {
  S_AXIS_DATA comb_0/M_AXIS
  aclk pll_0/clk_out1
  aresetn reset_sync_fir/aresetn_out
}

# Create axis_subset_converter
cell xilinx.com:ip:axis_subset_converter subset_0 {
  S_TDATA_NUM_BYTES.VALUE_SRC USER
  M_TDATA_NUM_BYTES.VALUE_SRC USER
  S_TDATA_NUM_BYTES 12
  M_TDATA_NUM_BYTES 8
  TDATA_REMAP {tdata[87:72],tdata[63:48],tdata[39:24],tdata[15:0]}
} {
  S_AXIS fir_0/M_AXIS_DATA
  aclk pll_0/clk_out1
  aresetn reset_sync_subset/aresetn_out
}

# ==============================================================================
# snareSAR Timing and Control Modules
# ==============================================================================

# PPS Synchronizer - 3-stage sync with falling edge detection
cell pavel-demin:user:pps_sync pps_sync_0 {} {
  aclk pll_0/clk_out1
  aresetn rst_0/peripheral_aresetn
  pps_in pps_in
}

# PRF Timing Generator - generates PRF pulses with PPS sync
cell pavel-demin:user:prf_timing prf_timing_0 {} {
  aclk pll_0/clk_out1
  aresetn rst_0/peripheral_aresetn
  prf_enable slice_prf_enable/dout
  pps_pulse pps_sync_0/pps_pulse
  prf_divider slice_prf_divider/dout
  trigger_width slice_trigger_width/dout
  txdata_out txdata_out
}

# Polarization Controller - RF switch control
cell pavel-demin:user:pol_controller pol_ctrl_0 {} {
  aclk pll_0/clk_out1
  aresetn rst_0/peripheral_aresetn
  prf_pulse prf_timing_0/prf_pulse
  pol_auto slice_pol_auto/dout
  pol_manual slice_pol_manual/dout
  pol_gpio pol_gpio
}

# ADF4159 SPI Interface - PLL configuration
# v1.5.0 C1: spi_start and spi_data now driven from CFG registers
#   spi_data  <- slice_adf_spi_data/dout  = cfg_data[191:160] (32 bits)
#   spi_start <- slice_adf_spi_start/dout = cfg_data[192]     (1 bit)
# Software protocol: write spi_data -> set spi_start=1 -> poll spi_busy
#   until 0 -> clear spi_start=0 -> repeat for next register.
# WARNING: spi_start is LEVEL-SENSITIVE. If left high after transaction
#   completes, the module will immediately fire again. Software MUST
#   clear spi_start after each transaction.
# v1.5.0 C7: spi_busy routed to STS[130] for software polling.
#   spi_done remains unconnected (single-cycle pulse, not useful for polling).
cell pavel-demin:user:adf4159_spi adf4159_spi_0 {} {
  aclk pll_0/clk_out1
  aresetn rst_0/peripheral_aresetn
  spi_start slice_adf_spi_start/dout
  spi_data slice_adf_spi_data/dout
  ce_out adf_ce
  clk_out adf_clk
  data_out adf_data
  le_out adf_le
  muxout_in muxout_in
}

# Range Gate - captures samples after delay
cell pavel-demin:user:axis_gate axis_gate_0 {} {
  aclk pll_0/clk_out1
  aresetn rst_0/peripheral_aresetn
  prf_pulse prf_timing_0/prf_pulse
  gate_delay slice_gate_delay/dout
  gate_duration slice_gate_duration/dout
  S_AXIS subset_0/M_AXIS
}

# v1.5.0 C2/C3: const_n_samples and const_flags REMOVED
# n_samples now driven from cfg_data[223:208] via slice_n_samples (C2)
# flags now driven from cfg_data[207:200] via slice_flags (C3)

# Header Insert - adds 16-byte header to each packet
# v1.5.0 C2: n_samples <- slice_n_samples/dout = cfg_data[223:208] (was const 100)
# v1.5.0 C3: flags     <- slice_flags/dout     = cfg_data[207:200] (was const 0x00)
cell pavel-demin:user:header_insert header_insert_0 {} {
  aclk pll_0/clk_out1
  aresetn rst_0/peripheral_aresetn
  prf_pulse prf_timing_0/prf_pulse
  prf_count prf_timing_0/prf_count
  pps_count prf_timing_0/pps_count
  n_samples slice_n_samples/dout
  pol pol_ctrl_0/current_pol
  flags slice_flags/dout
  S_AXIS axis_gate_0/M_AXIS
}

# Status Concatenation - combines status values for sts_data[159:0]
# sts_data[15:0]    = writer_addr (from writer_0, connected later)
# sts_data[31:16]   = reserved (zero)
# sts_data[63:32]   = prf_count
# sts_data[95:64]   = pps_count
# sts_data[127:96]  = prf_at_pps
# sts_data[128]     = current_pol   (v1.5.0 C4)
# sts_data[129]     = pps_level     (v1.5.0 C4)
# sts_data[130]     = spi_busy      (v1.5.0 C7)
# sts_data[159:131] = reserved (zero, padding)

# Constant zero for reserved bits [31:16]
cell xilinx.com:ip:xlconstant const_sts_reserved {
  CONST_WIDTH 16
  CONST_VAL 0
}

# v1.5.0 C4/C7: Constant zero for STS padding bits [159:131]
cell xilinx.com:ip:xlconstant const_sts_pad_29 {
  CONST_WIDTH 29
  CONST_VAL 0
}

# v1.5.0 C4/C7: sts_concat expanded from 5 ports (128 bits) to 9 ports (160 bits)
#   Ports 0-4: unchanged from v1.4.0
#   Port 5:    current_pol (C4)
#   Port 6:    pps_level   (C4)
#   Port 7:    spi_busy    (C7)
#   Port 8:    zero padding to fill 160-bit STS width
cell xilinx.com:ip:xlconcat sts_concat_0 {
  NUM_PORTS 9
  IN0_WIDTH 16
  IN1_WIDTH 16
  IN2_WIDTH 32
  IN3_WIDTH 32
  IN4_WIDTH 32
  IN5_WIDTH 1
  IN6_WIDTH 1
  IN7_WIDTH 1
  IN8_WIDTH 29
} {
  In1 const_sts_reserved/dout
  In2 prf_timing_0/prf_count
  In3 prf_timing_0/pps_count
  In4 prf_timing_0/prf_at_pps
  In5 pol_ctrl_0/current_pol
  In6 pps_sync_0/pps_level
  In7 adf4159_spi_0/spi_busy
  In8 const_sts_pad_29/dout
  dout hub_0/sts_data
}

# Create axis_packetizer
# v1.5.0 C5: CONTINUOUS FALSE->TRUE for streaming operation
# With CONTINUOUS=FALSE, the packetizer disables itself after one packet
# (axis_packetizer.v STOP block: int_enbl_next = 1'b0 on tlast).
# With CONTINUOUS=TRUE, it resets counter to zero and immediately re-arms,
# allowing continuous multi-packet streaming without reset cycles.
cell pavel-demin:user:axis_packetizer pktzr_0 {
  AXIS_TDATA_WIDTH 64
  CNTR_WIDTH 32
  CONTINUOUS TRUE
  ALWAYS_READY TRUE
} {
  S_AXIS header_insert_0/M_AXIS
  cfg_data slice_4/dout
  aclk pll_0/clk_out1
  aresetn slice_1/dout
}

# Create xlconstant
cell xilinx.com:ip:xlconstant const_1 {
  CONST_WIDTH 16
  CONST_VAL 65535
}

# Create axis_ram_writer
cell pavel-demin:user:axis_ram_writer writer_0 {
  ADDR_WIDTH 16
  AXI_ID_WIDTH 3
  AXIS_TDATA_WIDTH 64
  FIFO_WRITE_DEPTH 1024
} {
  S_AXIS pktzr_0/M_AXIS
  M_AXI ps_0/S_AXI_ACP
  min_addr slice_3/dout
  cfg_data const_1/dout
  sts_data sts_concat_0/In0
  aclk pll_0/clk_out1
  aresetn slice_2/dout
}
