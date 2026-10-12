# run - compile 

analyze -f verilog ./src/cpu_lite_top.v 
analyze -f verilog ./src/cpu_core.v 

analyze -f verilog ./src/cache.v 
analyze -f verilog ./src/cache_dm_control.v 
analyze -f verilog ./src/async_fifo.v 
analyze -f verilog ./src/reset_sync.v

elaborate cpu_lite_top 
link

check_design
 
write -format ddc -hier -output unmapped/cpu_lite.ddc
 
source cpu_const.sdc
 
write -format ddc -hier -output unmapped/cpu_lite.ddc
 
check_timing
compile_ultra
 
write -format verilog -hierarchy -output netlist/cpu_netlist.v
write -format ddc -hierarchy -output mapped/cpu.ddc


# Area report
report_area > area_report.rpt

# Clock reports
report_clocks > clocks_report.rpt
report_clock -skew > clock_skew_report.rpt

# Timing reports
report_timing -delay max -max_paths 20 > max_delay_report.rpt
report_timing -delay min -max_paths 20 > min_delay_report.rpt

# Constraint violations
report_constraint -all_violators > constraint_violators.rpt

# Quality of Results
report_qor > qor_report.rpt

