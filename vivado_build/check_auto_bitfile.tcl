open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
refresh_hw_device $dev

set part "s25fl128sxxxxxx0-spi-x1_x2_x4"
set cfgmem [create_hw_cfgmem -hw_device $dev [lindex [get_cfgmem_parts $part] 0]]
puts "Auto bitfile: [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]"

close_hw_target
close_hw_manager
exit 0
