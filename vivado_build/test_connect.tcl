open_hw_manager
puts "Connecting..."
connect_hw_server -url localhost:3121 -allow_non_jtag
puts "Targets:"
puts [get_hw_targets]
close_hw_manager
puts "SUCCESS!"
exit 0
