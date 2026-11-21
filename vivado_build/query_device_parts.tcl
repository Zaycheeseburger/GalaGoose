open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
refresh_hw_device $dev

puts "Supported cfgmem parts for $dev:"
set supported [get_cfgmem_parts -of_objects $dev]
puts "Total supported: [llength $supported]"
puts "Spansion parts: [get_cfgmem_parts -of_objects $dev *s25fl128*]"
puts "Micron parts: [get_cfgmem_parts -of_objects $dev *mt25q*]"
puts "N25Q parts: [get_cfgmem_parts -of_objects $dev *n25q128*]"
puts "Macronix parts: [get_cfgmem_parts -of_objects $dev *mx25l128*]"

close_hw_target
close_hw_manager
exit 0
