open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
refresh_hw_device $dev
puts "Target Frequency: [get_property PARAM.FREQUENCY [current_hw_target]]"
puts "Device status: [get_property STATUS $dev]"
puts "Registers:"
puts [report_property -all $dev]
close_hw_target
close_hw_manager
exit 0
