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
    
    print(f"Starting RF capture on ADC Channel {args.channels} at {args.freq:0.3f} MHz") 

    board_ip = '192.168.4.99'
    client_ip = '192.168.4.1'

    print("Initializing RFSoC 10G Overlay")
    ol = Overlay(ignore_version=True)

    # Wait for overlay to initialize
    time.sleep(5) 

    # Disable all ADC UDP streams
    ol.adc_to_udp_stream_A.register_map.USER_RESET = 1
    ol.adc_to_udp_stream_B.register_map.USER_RESET = 1
    ol.adc_to_udp_stream_C.register_map.USER_RESET = 1
    ol.adc_to_udp_stream_D.register_map.USER_RESET = 1

    # Set reference clocks
    lmx_freq=491.52

    # Config file for lmk_freq = 245.76 defaults to RFSoC VCO clock
    # xrfclk.set_ref_clks(lmk_freq=245.76, lmx_freq=lmx_freq)

    # Config file for lmk_freq = 122.88 also set clock reference to external
    xrfclk.set_ref_clks(lmk_freq=122.88, lmx_freq=lmx_freq)

    # Start ADC
    ADC_SAMPLE_FREQUENCY = 1024     # MSps
    ADC_DECIMATION = 16             # Default, not actively set

    pll_freq = lmx_freq             # MHz
    fs = ADC_SAMPLE_FREQUENCY
    tile = 2                        # ADC Tile 226
    f_c = -1*args.freq              # User input

    mixer_settings_block_0 = {
            'CoarseMixFreq':  xrfdc.COARSE_MIX_BYPASS,
            'EventSource':    xrfdc.EVNT_SRC_TILE,
            'FineMixerScale': xrfdc.MIXER_SCALE_1P0,
            'Freq':           f_c,
            'MixerMode':      xrfdc.MIXER_MODE_R2C,
            'MixerType':      xrfdc.MIXER_TYPE_FINE,
            'PhaseOffset':    0.0
            }

    block = 0       # ADC Block 0 (B)
    ol.rfdc.adc_tiles[tile].DynamicPLLConfig(1, pll_freq, fs)
    ol.rfdc.adc_tiles[tile].blocks[block].NyquistZone = 1
    ol.rfdc.adc_tiles[tile].blocks[block].MixerSettings = mixer_settings_block_0
    ol.rfdc.adc_tiles[tile].blocks[block].UpdateEvent(xrfdc.EVENT_MIXER)

    mixer_settings_block_1 = mixer_settings_block_0.copy()

    ol.rfdc.adc_tiles[tile].blocks[1].NyquistZone = 1
    ol.rfdc.adc_tiles[tile].blocks[1].MixerSettings = mixer_settings_block_1
    ol.rfdc.adc_tiles[tile].blocks[1].UpdateEvent(xrfdc.EVENT_MIXER)
    ol.rfdc.adc_tiles[tile].SetupFIFO(True)

    # Configure UDP Header for new sample rate
    ol.adc_to_udp_stream_A.register_map.SAMPLE_RATE_NUMERATOR_LSB = ADC_SAMPLE_FREQUENCY * 1e6
    ol.adc_to_udp_stream_B.register_map.SAMPLE_RATE_NUMERATOR_LSB = ADC_SAMPLE_FREQUENCY * 1e6

    # Set center frequency
    ol.adc_to_udp_stream_A.register_map.FREQUENCY_IDX =  f_c * 1e6
    ol.adc_to_udp_stream_B.register_map.FREQUENCY_IDX =  f_c * 1e6

    print(f"Starting UDP stream on: {args.channels}")

    # Wait for beginning of second to initiate capture
    current_time = time.time()
    start_time = current_time
    while((current_time - int(current_time)) > .5):
        time.sleep(.1)
        current_time = time.time()

    # Delay 100ms for PPS sync
    time.sleep(.1)
    current_time = time.time()

    # Set enable on next pps capture 
    if 'A' in args.channels:
        ol.adc_to_udp_stream_A.register_map.CTRL = 3 # Set A control reg to 0x11
    if 'B' in args.channels:
        ol.adc_to_udp_stream_B.register_map.CTRL = 3 # Set B control reg to 0x11
    if 'A' in args.channels:
        ol.adc_to_udp_stream_A.register_map.CTRL = 3 # Set C control reg to 0x11
    if 'D' in args.channels:
        ol.adc_to_udp_stream_B.register_map.CTRL = 3 # Set D control reg to 0x11

    # Set start time in UDP Header
    current_time_s = int(current_time) + 1          # Stream starts PPS edge
    samples_since_epoch = int(current_time_s * ((ADC_SAMPLE_FREQUENCY * 1e6)/ ADC_DECIMATION))
    samples_since_epoch_lsb = samples_since_epoch & 0xFFFFFFFF
    samples_since_epoch_msb = samples_since_epoch >> 32
    ol.adc_to_udp_stream_A.register_map.SAMPLE_IDX_OFFSET_LSB = samples_since_epoch_lsb
    ol.adc_to_udp_stream_A.register_map.SAMPLE_IDX_OFFSET_MSB = samples_since_epoch_msb
    ol.adc_to_udp_stream_B.register_map.SAMPLE_IDX_OFFSET_LSB = samples_since_epoch_lsb
    ol.adc_to_udp_stream_B.register_map.SAMPLE_IDX_OFFSET_MSB = samples_since_epoch_msb
    ol.adc_to_udp_stream_C.register_map.SAMPLE_IDX_OFFSET_LSB = samples_since_epoch_lsb
    ol.adc_to_udp_stream_C.register_map.SAMPLE_IDX_OFFSET_MSB = samples_since_epoch_msb
    ol.adc_to_udp_stream_D.register_map.SAMPLE_IDX_OFFSET_LSB = samples_since_epoch_lsb
    ol.adc_to_udp_stream_D.register_map.SAMPLE_IDX_OFFSET_MSB = samples_since_epoch_msb

    while(int(ol.adc_to_udp_stream_B.register_map.PPS_COUNTER) < 1):
        time.sleep(.01)
    end_time = time.time()

    print(f"Capture initiated at: {start_time}")
    print(f"Capture started at: {current_time_s} sample_offset: {samples_since_epoch}")

    print("Ctrl-C to exit")
    while(not exit_flag):
        time.sleep(1)
        print(".", end='', flush=True)

    print("Stopping UDP stream")
    ol.adc_to_udp_stream_A.register_map.CTRL = 1
    ol.adc_to_udp_stream_B.register_map.CTRL = 1
    ol.adc_to_udp_stream_C.register_map.CTRL = 1
    ol.adc_to_udp_stream_D.register_map.CTRL = 1

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
