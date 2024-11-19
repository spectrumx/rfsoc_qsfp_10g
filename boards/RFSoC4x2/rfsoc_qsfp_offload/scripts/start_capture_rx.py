import time
import signal
import sys
import argparse
from rfsoc_qsfp_offload.overlay import Overlay

global exit_flag

def signal_handler(sig, frame):
    print('')
    print('Exiting RF capture')
    global exit_flag
    exit_flag = True
    
def main(args):
    
    # Correct for ADC ordering
    if(args.channel == 0):
        adc_block = 1
    elif(args.channel == 1):
        adc_block = 0
    else:
        print("Invalid ADC Channel")
        return

    f_c = args.freq
    print("Starting RF capture on ADC%d at %0.3fMHz" % (args.channel, f_c))

    board_ip = '192.168.4.99'
    client_ip = '192.168.4.1'

    print("Initializing RFSoC QSFP Offload Overlay")
    #ol = Overlay(ignore_version=True)
    ol = Overlay(bitfile_name="../bitstream/rfsoc_offload_10g.bit", ignore_version=True)
    # Wait for overlay to initialize
    ol.cmac.mmio.write(0x107C, 0x3) # RSFEC_CONFIG_ENABLE
    ol.cmac.mmio.write(0x1000, 0x7) # RSFEC_CONFIG_INDICATION_CORRECTION
    time.sleep(5) # Magic sleep

    ol.cmac.start()
    res = ol.netlayer.set_ip_address(board_ip, debug=True)

    print("Network confguration complete IP: %s" % (res['inet addr']))

    ol.netlayer.sockets[0] = (client_ip, 60133, 60133, True)
    ol.netlayer.populate_socket_table()
    ol.adc_select(adc_block) # Select RF-ADC source for packets

    ADC_TILE = 2       # ADC Tile 226
    ADC_SAMPLE_FREQUENCY = 1024  # MSps
    ADC_PLL_FREQUENCY    = 491.52   # MHz
    ADC_FC = -1*f_c # Tune to center frequency

    # Stop UDP stream if running
    ol.enable_udp(False)

    # Start ADC
    ol.initialise_adc(tile=ADC_TILE,
                    block=adc_block,
                    pll_freq=ADC_PLL_FREQUENCY,
                    fs=ADC_SAMPLE_FREQUENCY,
                    fc=ADC_FC)

    # Decimate by (16x)
    ol.set_decimation(tile=ADC_TILE,block=adc_block,sample_rate=64e6)

    # Set packet size
    ol.enable_udp(True)

    print("Starting UDP stream")
    print("Ctrl-C to exit")
    while(not exit_flag):
        time.sleep(1)
        print(".", end='', flush=True)

    # Stop packet generator
    ol.enable_udp(False)

if __name__ == "__main__":
    # CTRL-C handler
    global exit_flag 
    exit_flag = False
    signal.signal(signal.SIGINT, signal_handler)

    parser = argparse.ArgumentParser(
        description='Tune RFSoC and stream data over QSFP',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
        )
    parser.add_argument('-f', '--freq',type=float,help='Center frequency (MHz)',
                        default = '1000')
    parser.add_argument('-c', '--channel',type=int,help='ADC Channel',
                        default = '0')
                        
    args = parser.parse_args()
    main(args)
