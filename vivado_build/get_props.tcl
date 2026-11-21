open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
refresh_hw_device $dev

set fp [open "dev_props.txt" "w"]
foreach prop [list_property $dev] {
    catch {
        puts $fp "$prop = [get_property $prop $dev]"
    }
}
close $fp
puts "PROPERTIES WRITTEN TO dev_props.txt"
close_hw_target
close_hw_manager
exit 0
