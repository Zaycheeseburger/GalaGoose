open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
refresh_hw_device $dev

# Set frequency to 6 MHz
set_property PARAM.FREQUENCY 6000000 [current_hw_target]
puts "Frequency: [get_property PARAM.FREQUENCY [current_hw_target]]"

set mcsfile "./space_shooter.mcs"
set part "s25fl128sxxxxxx0-spi-x1_x2_x4"

puts "Creating hw_cfgmem with Spansion part: $part..."
set cfgmem [create_hw_cfgmem -hw_device $dev [lindex [get_cfgmem_parts $part] 0]]

set_property PROGRAM.ADDRESS_RANGE {use_file} $cfgmem
set_property PROGRAM.FILES [list $mcsfile] $cfgmem
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $cfgmem
set_property PROGRAM.BLANK_CHECK 0 $cfgmem
set_property PROGRAM.ERASE 1 $cfgmem
set_property PROGRAM.CFG_PROGRAM 1 $cfgmem
set_property PROGRAM.VERIFY 1 $cfgmem
set_property PROGRAM.CHECKSUM 0 $cfgmem

puts "Starting programming for $part..."
if {[catch {program_hw_cfgmem -hw_cfgmem $cfgmem} err]} {
    puts "FAILED_SPANSION: $err"
} else {
    puts "SUCCESS_SPANSION: Flash successfully programmed!"
    boot_hw_device $dev
    puts "BOOTED_OK"
}

close_hw_target
close_hw_manager
exit 0
