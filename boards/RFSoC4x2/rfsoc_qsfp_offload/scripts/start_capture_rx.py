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
    
    f_c = args.freq
    print(f"Starting RF capture on ADC Channel {args.channels} at {f_c:0.3f} MHz") 

    board_ip = '192.168.4.99'
    client_ip = '192.168.4.1'

    print("Initializing RFSoC 10G Overlay")
    ol = Overlay(ignore_version=True)

    # Wait for overlay to initialize
    time.sleep(5) # Magic sleep
    ol.adc_to_udp_stream_A.register_map.USER_RESET = 1
    ol.adc_to_udp_stream_B.register_map.USER_RESET = 1

    # Start ADC
    ADC_TILE = 2       # ADC Tile 226
    ADC_SAMPLE_FREQUENCY = 1024  # MSps
    ADC_PLL_FREQUENCY    = 491.52   # MHz
    ADC_FC = -1*f_c # FM Band

    pll_freq = ADC_PLL_FREQUENCY
    fs = ADC_SAMPLE_FREQUENCY
    tile = ADC_TILE
    fc = ADC_FC

    mixer_settings = {
            'CoarseMixFreq':  xrfdc.COARSE_MIX_BYPASS,
            'EventSource':    xrfdc.EVNT_SRC_TILE,
            'FineMixerScale': xrfdc.MIXER_SCALE_1P0,
            'Freq':           fc,
            'MixerMode':      xrfdc.MIXER_MODE_R2C,
            'MixerType':      xrfdc.MIXER_TYPE_FINE,
            'PhaseOffset':    0.0
            }

    block = 0       # ADC Block 0 (B)
    ol.rfdc.adc_tiles[tile].DynamicPLLConfig(1, pll_freq, fs)
    ol.rfdc.adc_tiles[tile].blocks[block].NyquistZone = 1
    ol.rfdc.adc_tiles[tile].blocks[block].MixerSettings = mixer_settings
    ol.rfdc.adc_tiles[tile].blocks[block].UpdateEvent(xrfdc.EVENT_MIXER)
    ol.rfdc.adc_tiles[tile].SetupFIFO(True)

    block = 1       # ADC Block 1 (A)
    ol.rfdc.adc_tiles[tile].DynamicPLLConfig(1, pll_freq, fs)
    ol.rfdc.adc_tiles[tile].blocks[block].NyquistZone = 1
    ol.rfdc.adc_tiles[tile].blocks[block].MixerSettings = mixer_settings
    ol.rfdc.adc_tiles[tile].blocks[block].UpdateEvent(xrfdc.EVENT_MIXER)
    ol.rfdc.adc_tiles[tile].SetupFIFO(True)

    print(f"Starting UDP stream on: {args.channels}")
    if 'A' in args.channels:
        ol.adc_to_udp_stream_A.register_map.USER_RESET = 0
    if 'B' in args.channels:
        ol.adc_to_udp_stream_B.register_map.USER_RESET = 0

    print("Ctrl-C to exit")
    while(not exit_flag):
        time.sleep(1)
        print(".", end='', flush=True)

    print("Stopping UDP stream")
    ol.adc_to_udp_stream_A.register_map.USER_RESET = 1
    ol.adc_to_udp_stream_B.register_map.USER_RESET = 1

if __name__ == "__main__":
    # CTRL-C handler
    global exit_flag 
    exit_flag = False

    termination_signals = [
        signal.SIGINT,   # Ctrl+C
        signal.SIGTERM,  # Termination (kill)
        signal.SIGHUP,   # Hangup
        signal.SIGQUIT,  # Ctrl+\
        signal.SIGABRT,  # Aborted
    ]

    for sig in termination_signals:
        signal.signal(sig, signal_handler)

    parser = argparse.ArgumentParser(
        description='Tune RFSoC and stream data over QSFP',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
        )
    parser.add_argument('-f', '--freq',type=float,help='Center frequency (MHz)',
                        default = '1000')
    parser.add_argument('-c', '--channels',type=str,nargs='*',
                        choices=['A', 'B', 'C', 'D'], help='List of channels (A, B)',
                        default = 'A')
                        
    args = parser.parse_args()
    main(args)
