open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
refresh_hw_device $dev

# Lower JTAG frequency to 6MHz to be rock solid
set_property PARAM.FREQUENCY 6000000 [current_hw_target]
puts "New Target Frequency: [get_property PARAM.FREQUENCY [current_hw_target]]"

# Generate MCS file
set bitfile "./space_shooter.bit"
set mcsfile "./space_shooter.mcs"
puts "Generating MCS file..."
write_cfgmem -format mcs -size 16 -interface SPIx1 -loadbit "up 0x00000000 $bitfile" -force $mcsfile
puts "MCS generated."

set test_parts [list "s25fl128s-3.3v-qspi-x4-single" "s25fl128sxxxxxx0-spi-x1_x2_x4" "mt25ql128-spi-x1_x2_x4" "s25fl128s-3.3v-qspi-x1-single"]

foreach part $test_parts {
    puts "=========================================="
    puts "Testing part: $part"
    catch {delete_hw_cfgmem [get_hw_cfgmems]}
    set cfgmem [create_hw_cfgmem -hw_device $dev [lindex [get_cfgmem_parts $part] 0]]
    set_property PROGRAM.ADDRESS_RANGE {use_file} $cfgmem
    set_property PROGRAM.FILES [list $mcsfile] $cfgmem
    set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $cfgmem
    set_property PROGRAM.BLANK_CHECK 0 $cfgmem
    set_property PROGRAM.ERASE 1 $cfgmem
    set_property PROGRAM.CFG_PROGRAM 1 $cfgmem
    set_property PROGRAM.VERIFY 1 $cfgmem
    set_property PROGRAM.CHECKSUM 0 $cfgmem
    
    if {[catch {program_hw_cfgmem -hw_cfgmem $cfgmem} err]} {
        puts "FAILED for $part: $err"
    } else {
        puts "SUCCESS for $part!"
        boot_hw_device $dev
        puts "BOOTED_FROM_FLASH_SUCCESS"
        break
    }
}

close_hw_target
close_hw_manager
exit 0
