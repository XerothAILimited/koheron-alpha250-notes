# CE Tree Timing Fix - Aggressive Implementation Script
puts "CE TREE TIMING FIX BUILD"

# Open the existing project
open_project tmp/snare_sar.xpr

# Reset the implementation run to pick up new XDC constraints
reset_run impl_1

# Launch implementation with aggressive directives
set_property strategy Performance_ExtraTimingOpt [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraNetDelay_high [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveFanoutOpt [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Open the implemented design for analysis
open_run impl_1

# Generate timing reports
report_timing_summary -file tmp/snare_sar.runs/impl_1/ce_fix_timing_summary.rpt
report_timing -from [get_pins -hier -filter {NAME =~ *not_full_1_reg*/C}] \
              -to [get_pins -hier -filter {REF_NAME =~ DSP48* && NAME =~ */CE*}] \
              -max_paths 20 -file tmp/snare_sar.runs/impl_1/ce_fix_ce_paths.rpt

# Get and display the WNS
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
puts "==========================================="
puts "FINAL WNS: $wns ns"
puts "==========================================="

# Save checkpoint
write_checkpoint -force tmp/snare_sar.runs/impl_1/system_wrapper_ce_fix_routed.dcp

# Copy bitstream to expected location
file copy -force tmp/snare_sar.runs/impl_1/system_wrapper.bit tmp/snare_sar_ce_fix.bit

puts "Build complete."
close_project
