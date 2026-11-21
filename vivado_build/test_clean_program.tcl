open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
refresh_hw_device $dev

set binfile [file normalize "./space_shooter.bin"]
puts "BIN file: $binfile (exists: [file exists $binfile])"

set part "s25fl128sxxxxxx0-spi-x1_x2_x4"
set cfgmem [create_hw_cfgmem -hw_device $dev [lindex [get_cfgmem_parts $part] 0]]

set_property PROGRAM.FILES [list $binfile] $cfgmem
set_property PROGRAM.ERASE 1 $cfgmem
set_property PROGRAM.CFG_PROGRAM 1 $cfgmem
set_property PROGRAM.VERIFY 1 $cfgmem

puts "Attempting program_hw_cfgmem..."
if {[catch {program_hw_cfgmem -hw_cfgmem $cfgmem} err]} {
    puts "FAILED_CLEAN: $err"
} else {
    puts "SUCCESS_CLEAN: Flash programmed successfully!"
    boot_hw_device $dev
    puts "BOOTED_OK"
}

close_hw_target
close_hw_manager
exit 0
