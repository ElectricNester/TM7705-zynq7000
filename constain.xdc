# Clock pins (200 MHz differential LVDS)
set_property IOSTANDARD LVDS [get_ports clk_p]
set_property PACKAGE_PIN H9  [get_ports clk_p]

set_property IOSTANDARD LVDS [get_ports clk_n]
set_property PACKAGE_PIN G9  [get_ports clk_n]

create_clock -name clk_200m -period 5.000 [get_ports clk_p]

# Reset button
set_property IOSTANDARD LVCMOS33 [get_ports sysrst]
set_property PACKAGE_PIN AB12 [get_ports sysrst]
set_property PULLUP TRUE [get_ports sysrst]

# AD7705 SPI Interface
set_property IOSTANDARD LVCMOS33 [get_ports AD_CS]
set_property PACKAGE_PIN AH13 [get_ports AD_CS]

set_property IOSTANDARD LVCMOS33 [get_ports AD_clk]
set_property PACKAGE_PIN AJ15 [get_ports AD_clk]

set_property IOSTANDARD LVCMOS33 [get_ports AD_din]
set_property PACKAGE_PIN AK15 [get_ports AD_din]

set_property IOSTANDARD LVCMOS33 [get_ports AD_dout]
set_property PACKAGE_PIN AJ14 [get_ports AD_dout]

set_property IOSTANDARD LVCMOS33 [get_ports AD_DRDY_n]
set_property PACKAGE_PIN AJ13 [get_ports AD_DRDY_n]

# AD7705 Hardware Reset
set_property IOSTANDARD LVCMOS33 [get_ports AD_RST_n]
set_property PACKAGE_PIN AH14 [get_ports AD_RST_n]
set_property PULLUP TRUE [get_ports AD_RST_n]

# LED pins (7 LEDs) 
set_property IOSTANDARD LVCMOS33 [get_ports {leds[0]}]
set_property PACKAGE_PIN AA19 [get_ports {leds[0]}]

set_property IOSTANDARD LVCMOS33 [get_ports {leds[1]}]
set_property PACKAGE_PIN AB19 [get_ports {leds[1]}]

set_property IOSTANDARD LVCMOS33 [get_ports {leds[2]}]
set_property PACKAGE_PIN AB20 [get_ports {leds[2]}]

set_property IOSTANDARD LVCMOS33 [get_ports {leds[3]}]
set_property PACKAGE_PIN AD20 [get_ports {leds[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports {leds[4]}]
set_property PACKAGE_PIN AE20 [get_ports {leds[4]}]

# leds[5]
set_property IOSTANDARD LVCMOS33 [get_ports {leds[5]}]
set_property PACKAGE_PIN AD14 [get_ports {leds[5]}]

# leds[6] 
set_property IOSTANDARD LVCMOS33 [get_ports {leds[6]}]
set_property PACKAGE_PIN AD13 [get_ports {leds[6]}]


set_property IOSTANDARD LVCMOS33 [get_ports AD_DRDY_n]
set_property PACKAGE_PIN AJ13 [get_ports AD_DRDY_n]
set_property PULLUP TRUE [get_ports AD_DRDY_n]

# Disable PS7 check for PL-only design
set_property SEVERITY {Warning} [get_drc_checks ZPS7-1]

# Relax timing for LEDs
set_false_path -to [get_ports {leds[*]}]