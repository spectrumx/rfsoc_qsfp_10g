VIVADO_VERSION := 2021.1

all: vivado_prj

vivado_check:
	vivado -version | fgrep ${VIVADO_VERSION}

vivado_prj: vivado_check 
	$(MAKE) all -C ./boards/RFSoC4x2/rfsoc_qsfp_offload/

clean:
	$(MAKE) clean -C ./boards/RFSoC4x2/rfsoc_qsfp_offload/
