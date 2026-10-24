add wave -noupdate -divider {=====================}
add wave -noupdate -divider {         TB          }
add wave -noupdate -divider {=====================}

add wave -noupdate -divider {axi_soc_subsystem_tb}
add wave -position insertpoint sim:/axi_soc_subsystem_tb/*

add wave -noupdate -divider {=====================}
add wave -noupdate -divider { AXI SOC SUBSYSTEM   }
add wave -noupdate -divider {=====================}

add wave -noupdate -divider {axi_soc_subsystem_inst}
add wave -position insertpoint sim:/axi_soc_subsystem_tb/axi_soc_subsystem_inst/*

add wave -noupdate -divider {u_axi_lite_interconnect_1x4}
add wave -position insertpoint sim:/axi_soc_subsystem_tb/axi_soc_subsystem_inst/u_axi_lite_interconnect_1x4/*

add wave -noupdate -divider {u_axi_ram}
add wave -position insertpoint sim:/axi_soc_subsystem_tb/axi_soc_subsystem_inst/u_axi_ram/*

add wave -noupdate -divider {u_axi_uart}
add wave -position insertpoint sim:/axi_soc_subsystem_tb/axi_soc_subsystem_inst/u_axi_uart/*

#add wave -noupdate -divider {ram_inst}
#add wave -position insertpoint sim:/axi_soc_subsystem_tb/axi_soc_subsystem_inst/u_axi_ram/gen_xilinx/ram_inst/*

add wave -noupdate -divider {uart_i}
add wave -position insertpoint sim:/axi_soc_subsystem_tb/axi_soc_subsystem_inst/u_axi_uart/uart_i/*

add wave -noupdate -divider {u_axi_slave_reg_bank}
add wave -position insertpoint sim:/axi_soc_subsystem_tb/axi_soc_subsystem_inst/u_axi_slave_reg_bank/*

config wave -signalnamewidth 1