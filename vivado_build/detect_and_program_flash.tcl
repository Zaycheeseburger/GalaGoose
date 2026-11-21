# Vivado TCL script to generate configuration memory and program SPI Flash on Nexys A7-100T
set bitfile "./space_shooter.bit"
set binfile "./space_shooter.bin"

if {![file exists $bitfile]} {
    puts "ERROR: $bitfile does not exist"
    exit 1
}

# 1. Generate .bin memory configuration file (16 MB SPIx1)
puts "Generating SPI Flash BIN file from $bitfile..."
write_cfgmem -format bin -size 16 -interface SPIx1 -loadbit "up 0x00000000 $bitfile" -force $binfile
puts "Generated BIN: $binfile ([file size $binfile] bytes)"

# 2. Open Hardware Manager
open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag
set targets [get_hw_targets]
if {[llength $targets] == 0} {
    puts "ERROR: No hardware targets detected"
    exit 2
}

open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

# 3. Detect and Attach Configuration Memory Part
# Digilent Nexys A7 uses Spansion S25FL128S (s25fl128sxxxxxx0-spi-x1_x2_x4)
# In some board revisions Micron MT25QL128 (mt25ql128-spi-x1_x2_x4 / n25q128-3.3v-spi-x1_x2_x4) is used.
set candidates [list "s25fl128sxxxxxx0-spi-x1_x2_x4" "s25fl128s-3.3v-spi-x1_x2_x4" "mt25ql128-spi-x1_x2_x4" "n25q128-3.3v-spi-x1_x2_x4"]

set chosen_part ""
foreach cand $candidates {
    set p [get_cfgmem_parts -quiet $cand]
    if {$p ne ""} {
        puts "Found cfgmem part in Vivado catalog: $cand"
        if {$chosen_part eq ""} {
            set chosen_part $cand
        }
    }
}

if {$chosen_part eq ""} {
    set chosen_part "s25fl128sxxxxxx0-spi-x1_x2_x4"
}

puts "Attempting to create hw_cfgmem with part: $chosen_part"
set cfgmem [create_hw_cfgmem -hw_device $dev [lindex [get_cfgmem_parts $chosen_part] 0]]

# Set properties for programming
set_property PROGRAM.BLANK_CHECK  0 $cfgmem
set_property PROGRAM.ERASE        1 $cfgmem
set_property PROGRAM.CFG_PROGRAM  1 $cfgmem
set_property PROGRAM.VERIFY       1 $cfgmem
set_property PROGRAM.CHECKSUM     0 $cfgmem
set_property PROGRAM.ADDRESS_RANGE {use_file} $cfgmem
set_property PROGRAM.FILES [list $binfile] $cfgmem
set_property PROGRAM.PRM_FILE {} $cfgmem
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $cfgmem

# Program Flash Memory
puts "Starting Flash Memory programming (Erase, Program, Verify)..."
puts "This typically takes ~40-80 seconds. Please do not disconnect the board."
program_hw_cfgmem -hw_cfgmem $cfgmem

puts "FLASH_PROGRAM_SUCCESS: SPI Flash memory successfully programmed with $binfile"

# Boot from Flash immediately to verify
puts "Triggering FPGA configuration from SPI Flash..."
boot_hw_device $dev
refresh_hw_device $dev

puts "ALL_DONE_SUCCESSFULLY"
close_hw_target
close_hw_manager
exit 0
