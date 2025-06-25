# 156.25 MHz USER_MGT_SI570_CLOCK - XXV Ethernet input clock
set_property PACKAGE_PIN AA34 [get_ports diff_clock_rtl_clk_n]
set_property PACKAGE_PIN AA33 [get_ports diff_clock_rtl_clk_p]

## USER SLIDE SWITCH
#set_property PACKAGE_PIN AN13 [ get_ports "sw_0" ]
#set_property IOSTANDARD LVCMOS18 [ get_ports "sw_0" ]

set_property PACKAGE_PIN AU12 [get_ports sw_1]
set_property IOSTANDARD LVCMOS18 [get_ports sw_1]

set_property PACKAGE_PIN AW11 [get_ports sw_2]
set_property IOSTANDARD LVCMOS18 [get_ports sw_2]

## USER LED SWITCH
set_property PACKAGE_PIN AR11 [get_ports {led_0[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_0[0]}]

set_property PACKAGE_PIN AW10 [get_ports led_1]
set_property IOSTANDARD LVCMOS18 [get_ports led_1]

set_property PACKAGE_PIN AT11 [get_ports led_2]
set_property IOSTANDARD LVCMOS18 [get_ports led_2]

set_property PACKAGE_PIN AU10 [get_ports led_3]
set_property IOSTANDARD LVCMOS18 [get_ports led_3]

## QSFP PHY LAYER CONTROL
set_property PACKAGE_PIN AM22 [get_ports qsfp_intl_ls]
set_property IOSTANDARD LVCMOS18 [get_ports qsfp_intl_ls]

#set_property PACKAGE_PIN AL21 [ get_ports "qsfp_resetl_ls" ]
#set_property IOSTANDARD LVCMOS18 [ get_ports "qsfp_resetl_ls" ]

set_property PACKAGE_PIN AN22 [get_ports {qsfp_lpmode_ls[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {qsfp_lpmode_ls[0]}]

set_property PACKAGE_PIN AK22 [get_ports {qsfp_modsell_ls[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {qsfp_modsell_ls[0]}]

## PPS
set_property PACKAGE_PIN AJ13 [get_ports pps_comp_in]
set_property IOSTANDARD LVCMOS18 [get_ports pps_comp_in]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets pps_comp_in_IBUF_inst/O]

set_false_path -setup -from [get_clocks {RFADC0_CLK RFADC2_CLK}] -to [get_clocks *txoutclk_out*]
set_false_path -setup -from [get_clocks *clk_pl_0*] -to [get_clocks {RFADC0_CLK RFADC2_CLK}]

set_false_path -setup -from [get_clocks {RFADC0_CLK RFADC2_CLK}] -to [get_clocks *clk_pl_0*]
set_false_path -setup -from [get_clocks *txoutclk_out*] -to [get_clocks {RFADC0_CLK RFADC2_CLK}]


set_false_path -setup -from [get_clocks *clk_pl_0*] -to [get_clocks *txoutclk_out*]
set_false_path -setup -from [get_clocks *txoutclk_out*] -to [get_clocks *clk_pl_0*]
