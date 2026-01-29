# snareSAR Pin Constraints
# GPIO Mapping per Joe Earlam, 21 Jan 2026
# Alpha250 FPGA: Zynq-7020

# ==============================================================================
# ADF4159 SPI Interface (exp_p[0:3])
# ==============================================================================

# ADF4159 Chip Enable (exp_p[0])
set_property PACKAGE_PIN K14 [get_ports adf_ce]
set_property IOSTANDARD LVCMOS18 [get_ports adf_ce]
set_property SLEW FAST [get_ports adf_ce]

# ADF4159 SPI Clock (exp_p[1])
set_property PACKAGE_PIN L14 [get_ports adf_clk]
set_property IOSTANDARD LVCMOS18 [get_ports adf_clk]
set_property SLEW FAST [get_ports adf_clk]

# ADF4159 SPI Data (exp_p[2])
set_property PACKAGE_PIN M14 [get_ports adf_data]
set_property IOSTANDARD LVCMOS18 [get_ports adf_data]
set_property SLEW FAST [get_ports adf_data]

# ADF4159 Load Enable (exp_p[3])
set_property PACKAGE_PIN K19 [get_ports adf_le]
set_property IOSTANDARD LVCMOS18 [get_ports adf_le]
set_property SLEW FAST [get_ports adf_le]

# ==============================================================================
# Input Signals (exp_p[4:5])
# ==============================================================================

# ADF4159 MUXOUT (exp_p[4]) - Input
set_property PACKAGE_PIN L19 [get_ports muxout_in]
set_property IOSTANDARD LVCMOS18 [get_ports muxout_in]

# PPS Input (exp_p[5]) - Input
set_property PACKAGE_PIN H16 [get_ports pps_in]
set_property IOSTANDARD LVCMOS18 [get_ports pps_in]

# ==============================================================================
# RF Control (exp_p[6:7])
# ==============================================================================

# RF Switch / Polarization GPIO (exp_p[6])
set_property PACKAGE_PIN M19 [get_ports pol_gpio]
set_property IOSTANDARD LVCMOS18 [get_ports pol_gpio]
set_property SLEW FAST [get_ports pol_gpio]

# TXDATA Output (exp_p[7]) - Connected 28 Jan 2026
set_property PACKAGE_PIN N15 [get_ports txdata_out]
set_property IOSTANDARD LVCMOS18 [get_ports txdata_out]
set_property SLEW FAST [get_ports txdata_out]

# ==============================================================================
# Timing Constraints
# ==============================================================================

# False paths for asynchronous inputs
# PPS is 1 Hz, MUXOUT is used for lock detect polling
set_false_path -from [get_ports pps_in]
set_false_path -from [get_ports muxout_in]
