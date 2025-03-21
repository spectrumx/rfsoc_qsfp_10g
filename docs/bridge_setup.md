# Networking bridge setup

The default RFSoC 4x2 image uses a 100G Ethernet Subsystem IP core to drive the QSFP interface. This core does not support lower data rates (10, 25, 40, etc.)
To connect to a system with a 10G NIC, either a 100G switch or a PC with two NICs needs to be placed between the RFSoC and the 10G device. 

## Use bridge utils to bridge interfaces
Install bridge utils
`sudo apt install bridge-utils`

Use the gnome network manager to configure static IPs on the input and output interfaces. Also set the MTU for each interface to 9000.
*192.168.4.2 (Input)
*192.168.4.3 (Output)

Configure Netplan:
Open /etc/netplan/01-netcfg.yaml and set up the bridge with both interfaces, but avoid assigning duplicate IPs to the bridge itself. Instead, assign the IP addresses directly to the NICs before adding them to the bridge:

network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: no
      addresses: [192.168.4.2/24]
    eth1:
      dhcp4: no
      addresses: [192.168.4.3/24]
  bridges:
    br0:
      interfaces: [eth0, eth1]
      parameters:
        stp: true  # Enable Spanning Tree Protocol (optional but recommended)

Apply the configuration

sudo netplan apply
