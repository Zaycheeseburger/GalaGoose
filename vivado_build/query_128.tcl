open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
refresh_hw_device $dev

puts "ALL 128Mb parts for $dev:"
foreach p [get_cfgmem_parts -of_objects $dev *128*] {
    puts "PART: $p"
}

close_hw_target
close_hw_manager
exit 0
