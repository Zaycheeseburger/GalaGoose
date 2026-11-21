open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
refresh_hw_device $dev

set spi_bitfile "D:/Vivado/2024.2/data/xicom/cfgmem/bitfile/spi_xc7a100t_pullnone.bit"
puts "Step 1: Manually programming FPGA with SPI helper bitstream: $spi_bitfile"
set_property PROGRAM.FILE $spi_bitfile $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "Step 1 Complete: Device is now running SPI helper core."

set mcsfile [file normalize "./space_shooter.mcs"]
set part "s25fl128sxxxxxx0-spi-x1_x2_x4"

puts "Step 2: Creating cfgmem with part $part..."
set cfgmem [create_hw_cfgmem -hw_device $dev [lindex [get_cfgmem_parts $part] 0]]
set_property PROGRAM.FILES [list $mcsfile] $cfgmem
set_property PROGRAM.ERASE 1 $cfgmem
set_property PROGRAM.CFG_PROGRAM 1 $cfgmem
set_property PROGRAM.VERIFY 1 $cfgmem

puts "Step 3: Running program_hw_cfgmem..."
if {[catch {program_hw_cfgmem $cfgmem} err]} {
    puts "FAILED_HELPER: $err"
} else {
    puts "SUCCESS_HELPER: Flash successfully programmed!"
    boot_hw_device $dev
    puts "BOOTED_OK"
}

close_hw_target
close_hw_manager
exit 0
