# RFSoC Data Offload
This repository is a fork of strath-sdr/rfsoc_qsfp_offload which has been modified to support lower data rates and a selectable ADC input. 

It contains an RFSoC4x2 reference design that enables high-speed data offload from the board to a PC/server, via the QSFP28 connection. The RF-ADC data is packetised into UDP packets and sent to the first SFP port on the RFSoC 4x2 QSFP28 connector via Xilinx's XXV Ethernet IP core.

## Equipment and Software Requirements
The following is a list of equipment and software used for development and testing of this design. Compatibility with any other software/equipment not listed here is not guaranteed.

### Hardware
- [RFSoC4x2 Development Board](https://www.rfsoc-pynq.io)
- Intel 10GbE x520 SFP NIC
- QSFP to SFP+ Adapter
- SFP+ Direct Attach Cable
- Computer with x520 NIC installed

### Software
- [PYNQ v2.7](http://www.pynq.io/board.html)
- [Jupyter-Lab](https://jupyter.org/)


## PYNQ (RFSoC 4x2) Installation Guide
Follow the instructions below to install the data offload example for PYNQ. You will need to give your board access to the internet.
* Power on your development board with an SD Card containing a PYNQ v2.7 image.
* Use ssh to open a terminal on the PNYQ system and navigate to a directory where the xilinx user has write permissions.
* Close this repository and cd into the repository directory.
```bash

pip3 install .
```
Once installation has complete you will find the package folder in the Jupyter workspace directory. The folder will be named 'rfsoc-offload'.

## Build Guide
The following software is required to build the project files in this repository.
* Vitis Core Development Kit 2021.1 with [Y2K22](https://support.xilinx.com/s/article/76960?language=en_US) patch applied
* Vivado Design Suite 2021.1
* Git

### Building the Project
To build the project, first make sure Vitis and Vivado are on your `$PATH` environment variable.

```
source <path-to-Vitis>/2021.1/settings64.sh
echo $PATH
```

Clone this project to a local directory and run `make` in the reposotiry top level directory.

```
make all
```

This will build the Vivado project, and generate the bitstream and HWH files required for the overlay. 
```make all``` can be re-run after ```make clean``` command is issued.

## PC/Server Setup

### Static IP 
To run this demo, the PC has to be setup to use a static IP of 192.168.4.1 for the QSFP interface.

Example using Gnome network manager interface:

<p align="center">
  <img src="./assets/static_ip_gnome.png" width="40%" height="40%" />
</p>

### MTU
For the best performance the Maximum Transmission Unit of the interface needs to be increased to support jumbo frames (MTU=9000).

Example using Gnome network manager interface:

<p align="center">
  <img src="./assets/MTU_gnome.png" width="40%" height="40%" />
</p>

### GNU Radio
Instructions on installing GNU Radio and preparing to run the demo can be found in [gnuradio/README.md](gnuradio/README.md).
