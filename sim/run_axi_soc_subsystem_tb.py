#Running with VUNIT revision from 21/12/2024 12:22:36 AM - SHA-1: 95f5959ea2a6b72d3cb3e774c5f6ae263832b512

from pathlib import Path                                  
from vunit import VUnit                                  
                                  
ROOT = Path(__file__).parent / "../"     
                                  
# Call Vunit addons
VU = VUnit.from_argv()
VU.add_vhdl_builtins()
VU.add_verification_components()

# Source files                                
LIB = VU.add_library("lib")
LIB.add_source_files( ROOT / "rtl_common"/ "src" / "axi_fifo.vhd")
LIB.add_source_files( ROOT / "rtl_common"/ "src" / "axi_interconnect_single.vhd")
LIB.add_source_files( ROOT / "rtl_common"/ "src" / "axi_lite_interconnect.vhd")
LIB.add_source_files( ROOT / "rtl_common"/ "src" / "axi_lite_interconnect_pkg.vhd")
LIB.add_source_files( ROOT / "rtl_common"/ "src" / "axi_ram.vhd")
LIB.add_source_files( ROOT / "src" / "axi_soc_subsystem.vhd")
LIB.add_source_files( ROOT / "rtl_common"/ "src" / "axi_uart.vhd")
LIB.add_source_files( ROOT / "rtl_common"/ "src" / "uart.vhd")
LIB.add_source_files( ROOT / "rtl_common"/ "src" / "rams_sp_wf.vhd")
LIB.add_source_files( ROOT / "rtl_common"/ "src" / "rams_sp_wf_pkg.vhd")
LIB.add_source_files( ROOT / "rtl_common"/ "src" / "axi_gpio.vhd")
LIB.add_source_files( ROOT / "rtl_common"/ "src" / "axi_slave_reg_bank_pkg.vhd")
LIB.add_source_files( ROOT / "rtl_common"/ "src" / "axi_slave_reg_bank.vhd")
LIB.add_source_files( ROOT /  "src" / "timestamp_pkg.vhd")

#Libraries
LIB.add_source_files( ROOT / "tb" / "axi_soc_subsystem_tb.vhd")

# Modelsim options
VU.set_sim_option('modelsim.init_files.after_load', [str(ROOT / 'sim' / 'wave_axi_soc_subsystem_tb.do')])
VU.set_sim_option('modelsim.vsim_flags', ["-voptargs=\"+acc\""])

VU.main()