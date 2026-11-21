open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
refresh_hw_device $dev

set mcsfile [file normalize "./space_shooter.mcs"]
set part "s25fl128sxxxxxx0-spi-x1_x2_x4"

set cfgmem [create_hw_cfgmem -hw_device $dev [lindex [get_cfgmem_parts $part] 0]]
set_property PROGRAM.FILES [list $mcsfile] $cfgmem
set_property PROGRAM.ERASE 1 $cfgmem
set_property PROGRAM.CFG_PROGRAM 1 $cfgmem
set_property PROGRAM.VERIFY 1 $cfgmem

puts "Running program_hw_cfgmem -verbose with operations set:"
catch {program_hw_cfgmem -verbose $cfgmem} res
puts "RESULT:"
puts $res

close_hw_target
close_hw_manager
exit 0
