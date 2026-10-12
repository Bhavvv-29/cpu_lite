create_clock -name CLK_Fast -period 6.667 [get_ports CLK_Fast]
create_clock -name CLK_Slow -period 14.285 [get_ports CLK_Slow]

set_clock_groups -asynchronous -group [get_clocks CLK_Fast] -group [get_clocks CLK_Slow]

set_clock_uncertainty -setup 0.06667 [get_clocks CLK_Fast]
set_clock_uncertainty -setup 0.14285 [get_clocks CLK_Slow]

set_false_path -from [get_ports RSTn]
 
