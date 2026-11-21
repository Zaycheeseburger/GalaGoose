# Vivado Hardware Manager Batch Programming Script for Nexys A7-100T
set bitfile "./space_shooter.bit"

if {![file exists $bitfile]} {
    puts "ERROR: Bitstream not found at $bitfile"
    exit 1
}

open_hw_manager
connect_hw_server -allow_non_jtag

set targets [get_hw_targets]
if {[llength $targets] == 0} {
    puts "NO_BOARD_CONNECTED: No Vivado hardware targets detected."
    close_hw_manager
    exit 2
}

puts "Detected hardware targets: $targets"
if {[catch {open_hw_target} err]} {
    puts "NO_BOARD_CONNECTED: Failed to open hardware target: $err"
    close_hw_manager
    exit 2
}

set dev [lindex [get_hw_devices xc7a100t*] 0]
if {$dev eq ""} {
    puts "NO_TARGET_DEVICE: xc7a100t device not found on JTAG chain. Found: [get_hw_devices]"
    close_hw_target
    close_hw_manager
    exit 3
}

current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
set_property PROGRAM.FILE $bitfile $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "PROGRAMMED_OK: Successfully programmed $dev with $bitfile"

close_hw_target
close_hw_manager
