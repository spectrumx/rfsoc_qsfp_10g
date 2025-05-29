import time
import signal
import sys
import argparse
import xrfdc
import xrfclk
from rfsoc_qsfp_offload.overlay import Overlay

global exit_flag

def signal_handler(sig, frame):
    print('')
    print('Exiting RF capture')
    global exit_flag
    exit_flag = True
    
def main(args):
    
    adc_channel = 0
    f_c = args.freq
    print("Starting RF capture on ADC%d at %0.3fMHz" % (adc_channel, f_c))

    board_ip = '192.168.4.99'
    client_ip = '192.168.4.1'

    print("Initializing RFSoC 10G Overlay")
    ol = Overlay(ignore_version=True)

    # Wait for overlay to initialize
    time.sleep(5) # Magic sleep

    print("Network confguration complete IP: %s" % (board_ip))

    # Start ADC
    ADC_TILE = 2       # ADC Tile 226
    ADC_SAMPLE_FREQUENCY = 1024  # MSps
    ADC_PLL_FREQUENCY    = 491.52   # MHz
    ADC_FC = -1*f_c # FM Band

    pll_freq = ADC_PLL_FREQUENCY
    fs = ADC_SAMPLE_FREQUENCY
    tile = ADC_TILE
    fc = ADC_FC

    block = 1       # ADC Block 1 (A)
    ol.rfdc.adc_tiles[tile].DynamicPLLConfig(1, pll_freq, fs)
    ol.rfdc.adc_tiles[tile].blocks[block].NyquistZone = 1
    ol.rfdc.adc_tiles[tile].blocks[block].MixerSettings = {
                'CoarseMixFreq':  xrfdc.COARSE_MIX_BYPASS,
                'EventSource':    xrfdc.EVNT_SRC_TILE,
                'FineMixerScale': xrfdc.MIXER_SCALE_1P0,
                'Freq':           fc,
                'MixerMode':      xrfdc.MIXER_MODE_R2C,
                'MixerType':      xrfdc.MIXER_TYPE_FINE,
                'PhaseOffset':    0.0
            }
    ol.rfdc.adc_tiles[tile].blocks[block].UpdateEvent(xrfdc.EVENT_MIXER)
    ol.rfdc.adc_tiles[tile].SetupFIFO(True)

    block = 0       # ADC Block 0 (B)
    ol.rfdc.adc_tiles[tile].DynamicPLLConfig(1, pll_freq, fs)
    ol.rfdc.adc_tiles[tile].blocks[block].NyquistZone = 1
    ol.rfdc.adc_tiles[tile].blocks[block].MixerSettings = {
                'CoarseMixFreq':  xrfdc.COARSE_MIX_BYPASS,
                'EventSource':    xrfdc.EVNT_SRC_TILE,
                'FineMixerScale': xrfdc.MIXER_SCALE_1P0,
                'Freq':           fc,
                'MixerMode':      xrfdc.MIXER_MODE_R2C,
                'MixerType':      xrfdc.MIXER_TYPE_FINE,
                'PhaseOffset':    0.0
            }
    ol.rfdc.adc_tiles[tile].blocks[block].UpdateEvent(xrfdc.EVENT_MIXER)
    ol.rfdc.adc_tiles[tile].SetupFIFO(True)

    print(f"Starting UDP stream on: {args.channels}")
    ol.adc_to_udp_stream_A.register_map.USER_RESET = 0
    ol.adc_to_udp_stream_B.register_map.USER_RESET = 0

    print("Ctrl-C to exit")
    while(not exit_flag):
        time.sleep(1)
        print(".", end='', flush=True)


    print("Stopping UDP stream")
    if 'A' in args.channels:
        ol.adc_to_udp_stream_A.register_map.USER_RESET = 0
    if 'B' in args.channels:
        ol.adc_to_udp_stream_B.register_map.USER_RESET = 0

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
    parser.add_argument('-c', '--channels',type=str,nargs='+',
                        choices=['A', 'B', 'C', 'D'], help='List of channels (A, B)',
                        default = 'A')
                        
    args = parser.parse_args()
    main(args)
