# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  ipgui::add_param $IPINST -name "C_M00_AXIS_TDATA_WIDTH" -widget comboBox
  ipgui::add_param $IPINST -name "C_M00_AXIS_TKEEP_WIDTH"

}

proc update_PARAM_VALUE.C_M00_AXIS_TKEEP_WIDTH { PARAM_VALUE.C_M00_AXIS_TKEEP_WIDTH } {
	# Procedure called to update C_M00_AXIS_TKEEP_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_M00_AXIS_TKEEP_WIDTH { PARAM_VALUE.C_M00_AXIS_TKEEP_WIDTH } {
	# Procedure called to validate C_M00_AXIS_TKEEP_WIDTH
	return true
}

proc update_PARAM_VALUE.C_S00_AXI_ADDR_WIDTH { PARAM_VALUE.C_S00_AXI_ADDR_WIDTH } {
	# Procedure called to update C_S00_AXI_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S00_AXI_ADDR_WIDTH { PARAM_VALUE.C_S00_AXI_ADDR_WIDTH } {
	# Procedure called to validate C_S00_AXI_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.C_S00_AXI_DATA_WIDTH { PARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to update C_S00_AXI_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S00_AXI_DATA_WIDTH { PARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to validate C_S00_AXI_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.FINAL_STATE { PARAM_VALUE.FINAL_STATE } {
	# Procedure called to update FINAL_STATE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.FINAL_STATE { PARAM_VALUE.FINAL_STATE } {
	# Procedure called to validate FINAL_STATE
	return true
}

proc update_PARAM_VALUE.PAYLOAD_LENGTH { PARAM_VALUE.PAYLOAD_LENGTH } {
	# Procedure called to update PAYLOAD_LENGTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PAYLOAD_LENGTH { PARAM_VALUE.PAYLOAD_LENGTH } {
	# Procedure called to validate PAYLOAD_LENGTH
	return true
}

proc update_PARAM_VALUE.C_M00_AXIS_TDATA_WIDTH { PARAM_VALUE.C_M00_AXIS_TDATA_WIDTH } {
	# Procedure called to update C_M00_AXIS_TDATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_M00_AXIS_TDATA_WIDTH { PARAM_VALUE.C_M00_AXIS_TDATA_WIDTH } {
	# Procedure called to validate C_M00_AXIS_TDATA_WIDTH
	return true
}


proc update_MODELPARAM_VALUE.C_M00_AXIS_TDATA_WIDTH { MODELPARAM_VALUE.C_M00_AXIS_TDATA_WIDTH PARAM_VALUE.C_M00_AXIS_TDATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_M00_AXIS_TDATA_WIDTH}] ${MODELPARAM_VALUE.C_M00_AXIS_TDATA_WIDTH}
}

proc update_MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH { MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH PARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_S00_AXI_DATA_WIDTH}] ${MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH { MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH PARAM_VALUE.C_S00_AXI_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_S00_AXI_ADDR_WIDTH}] ${MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.C_M00_AXIS_TKEEP_WIDTH { MODELPARAM_VALUE.C_M00_AXIS_TKEEP_WIDTH PARAM_VALUE.C_M00_AXIS_TKEEP_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_M00_AXIS_TKEEP_WIDTH}] ${MODELPARAM_VALUE.C_M00_AXIS_TKEEP_WIDTH}
}

proc update_MODELPARAM_VALUE.FINAL_STATE { MODELPARAM_VALUE.FINAL_STATE PARAM_VALUE.FINAL_STATE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.FINAL_STATE}] ${MODELPARAM_VALUE.FINAL_STATE}
}

proc update_MODELPARAM_VALUE.PAYLOAD_LENGTH { MODELPARAM_VALUE.PAYLOAD_LENGTH PARAM_VALUE.PAYLOAD_LENGTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PAYLOAD_LENGTH}] ${MODELPARAM_VALUE.PAYLOAD_LENGTH}
}

