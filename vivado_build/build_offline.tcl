# Vivado 2024.2 Non-Project Batch Build Script for GALAGOOSE (Nexys A7-100T)
# Run from D:/vivado_pj/Space_Shooter/vivado_build with TEMP/TMP set on D:
set_param general.maxThreads 1

set part "xc7a100tcsg324-1"
set top_module "space_shooter_top"

file mkdir ./reports
file mkdir ./checkpoints

# Read RTL sources
read_verilog ../rtl/clk_gen.v
read_verilog ../rtl/vga_sync.v
read_verilog ../rtl/peripherals.v
read_verilog ../rtl/bram_roms.v
read_verilog ../rtl/audio_synth.v
read_verilog -sv ../rtl/game_engine.sv
read_verilog -sv ../rtl/display_renderer.sv
read_verilog -sv ../rtl/space_shooter_top.sv

# Read BRAM initialization memory files
read_mem [glob ../mem/*.mem]

# Read constraints
read_xdc ../constrs/nexys_a7_space.xdc

# Synthesize
synth_design -top $top_module -part $part -flatten_hierarchy rebuilt
write_checkpoint -force ./checkpoints/post_synth.dcp
report_utilization -file ./reports/post_synth_util.rpt

# Optimize, Place, Route
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force ./checkpoints/post_route.dcp

# Reports
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 10 -file ./reports/timing_summary.rpt
report_utilization -file ./reports/util_summary.rpt
report_drc -file ./reports/drc.rpt

# Generate Bitstream
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
write_bitstream -force ./space_shooter.bit
puts "BITSTREAM COMPLETE: ./space_shooter.bit"

# Generate Flash MCS file (16MB Spansion S25FL128S SPIx1)
write_cfgmem -format mcs -size 16 -interface SPIx1 -loadbit "up 0x00000000 ./space_shooter.bit" -force ./space_shooter.mcs
puts "MCS FLASH IMAGE COMPLETE: ./space_shooter.mcs"
