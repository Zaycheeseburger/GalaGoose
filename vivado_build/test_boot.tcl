open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
puts "Triggering boot_hw_device..."
boot_hw_device $dev
refresh_hw_device $dev
puts "Refreshed."
close_hw_target
close_hw_manager
exit 0
