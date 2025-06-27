import time
import signal
import sys
import argparse
import logging
import termios
import tty
import xrfdc
import xrfclk
import zmq
from rfsoc_qsfp_offload.overlay import Overlay
from enum import Enum

global exit_flag

GREEN = "\033[92m"
BLUE = "\033[94m"
RED = "\033[91m"
RESET = "\033[0m"

all_channels = ['A', 'B', 'C', 'D']

class Ctrl(Enum):
    CAPTURE = 0
    RESET = 1
    CAPTURE_NEXT_PPS = 3

def signal_handler(sig, frame):
    logging.info('')
    logging.info('Exiting RF capture')
    global exit_flag
    exit_flag = True
    
def main(args):
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
 
    logging.info(f"Starting RF capture on ADC Channel {BLUE}{args.channels}{RESET} at {BLUE}{args.freq:0.3f} MHz{RESET}") 

    board_ip = '192.168.4.99'
    client_ip = '192.168.4.1'

    # ZMQ context and sockets
    sub_socket_str = "tcp://192.168.20.1:60200"
    logging.info(f"ZMQ Subscribe to {sub_socket_str}")
    context = zmq.Context()

    # Subscriber socket
    sub_socket = context.socket(zmq.SUB)
    sub_socket.connect(sub_socket_str)
    sub_socket.setsockopt_string(zmq.SUBSCRIBE, "cmd") 

    # Poller to handle non-blocking message checking
    poller = zmq.Poller()
    poller.register(sub_socket, zmq.POLLIN)

    logging.info("Initializing RFSoC 10G Overlay")
    ol = Overlay(ignore_version=True)

    # Wait for overlay to initialize
    time.sleep(5) 

    # Disable all ADC UDP streams
    set_channel_ctrl(ol, all_channels, Ctrl.RESET)

    # Set reference clocks
    lmx_freq=491.52

    # Config file for lmk_freq = 245.76 defaults to RFSoC VCO clock
    # xrfclk.set_ref_clks(lmk_freq=245.76, lmx_freq=lmx_freq)

    # Config file for lmk_freq = 122.88 defaults to external clock reference
    xrfclk.set_ref_clks(lmk_freq=122.88, lmx_freq=lmx_freq)

    # Start ADC
    ADC_SAMPLE_FREQUENCY = 1024     # MSps
    ADC_DECIMATION = 16             # Default, not actively set

    pll_freq = lmx_freq             # MHz
    fs = ADC_SAMPLE_FREQUENCY
    f_c = -1*args.freq              # User input

    mixer_settings_block = {
            'CoarseMixFreq':  xrfdc.COARSE_MIX_BYPASS,
            'EventSource':    xrfdc.EVNT_SRC_TILE,
            'FineMixerScale': xrfdc.MIXER_SCALE_1P0,
            'Freq':           f_c,
            'MixerMode':      xrfdc.MIXER_MODE_R2C,
            'MixerType':      xrfdc.MIXER_TYPE_FINE,
            'PhaseOffset':    0.0
            }

    # Configure all ADC channels to same f_c
    adc_tile_block = ((0,0), (0,1), (2,0), (2,1))
    mixer_blocks = [mixer_settings_block.copy(), mixer_settings_block.copy(), 
                   mixer_settings_block.copy(), mixer_settings_block.copy()]

    for (tile, block), mixer in zip(adc_tile_block, mixer_blocks):
        ol.rfdc.adc_tiles[tile].DynamicPLLConfig(1, pll_freq, fs)
        ol.rfdc.adc_tiles[tile].blocks[block].NyquistZone = 1
        ol.rfdc.adc_tiles[tile].blocks[block].MixerSettings = mixer
        ol.rfdc.adc_tiles[tile].blocks[block].UpdateEvent(xrfdc.EVENT_MIXER)
        ol.rfdc.adc_tiles[tile].SetupFIFO(True)

    logging.info(f"Starting UDP stream on: {BLUE}{args.channels}{RESET}")

    # Set center frequency
    set_freq_metadata(ol, args.channels, f_c * 1e6)
    set_sample_rate_metadata(ol, args.channels, ADC_SAMPLE_FREQUENCY * 1e6)

    # Set enable on next pps capture 
    # Configure UDP Header for new sample rate
    sample_rate = ((ADC_SAMPLE_FREQUENCY * 1e6)/ ADC_DECIMATION)
    capture_next_pps(ol, args.channels, sample_rate)

    global exit_flag
    pps_count_last = 0
    print("CTRL-C to exit")
    while(not exit_flag):
        # Check for incoming messages with 10ms timeout
        socks = dict(poller.poll(timeout=10))

        if sub_socket in socks:
            message = sub_socket.recv_string()
            zmq_cmd_handler(ol, args.channels, message, sample_rate)

        pps_count = max(
            int(ol.adc_to_udp_stream_A.register_map.PPS_COUNTER),
            int(ol.adc_to_udp_stream_B.register_map.PPS_COUNTER),
            int(ol.adc_to_udp_stream_C.register_map.PPS_COUNTER),
            int(ol.adc_to_udp_stream_D.register_map.PPS_COUNTER))
        if(pps_count > pps_count_last):
            print(f"\rElapsed capture time: {BLUE}{pps_count}{RESET}", end='', flush=True)

    logging.info("Stopping UDP stream")
    set_channel_ctrl(ol, all_channels, Ctrl.RESET)

def set_sample_rate_metadata(ol, channels, sample_rate):
    if 'A' in args.channels:
        ol.adc_to_udp_stream_A.register_map.SAMPLE_RATE_NUMERATOR_LSB = sample_rate
    if 'B' in args.channels:
        ol.adc_to_udp_stream_B.register_map.SAMPLE_RATE_NUMERATOR_LSB = sample_rate
    if 'C' in args.channels:
        ol.adc_to_udp_stream_C.register_map.SAMPLE_RATE_NUMERATOR_LSB = sample_rate
    if 'D' in args.channels:
        ol.adc_to_udp_stream_D.register_map.SAMPLE_RATE_NUMERATOR_LSB = sample_rate

def set_freq_metadata(ol, channels, f_c_hz):
    logging.info("Setting frequency metadata to; {f_c_hz}")
    if 'A' in channels:
        ol.adc_to_udp_stream_A.register_map.FREQUENCY_IDX =  f_c_hz
    if 'B' in channels:
        ol.adc_to_udp_stream_B.register_map.FREQUENCY_IDX =  f_c_hz 
    if 'C' in channels:
        ol.adc_to_udp_stream_C.register_map.FREQUENCY_IDX =  f_c_hz
    if 'D' in channels:
        ol.adc_to_udp_stream_D.register_map.FREQUENCY_IDX =  f_c_hz 

def capture_now(ol, channels):
    set_channel_ctrl(ol, channels, Ctrl.RESET)
    if 'A' in channels:
        ol.adc_to_udp_stream_A.register_map.SAMPLE_IDX_OFFSET_LSB = 0
        ol.adc_to_udp_stream_A.register_map.SAMPLE_IDX_OFFSET_MSB = 0
    if 'B' in channels:
        ol.adc_to_udp_stream_B.register_map.SAMPLE_IDX_OFFSET_LSB = 0
        ol.adc_to_udp_stream_B.register_map.SAMPLE_IDX_OFFSET_MSB = 0
    if 'C' in channels:
        ol.adc_to_udp_stream_C.register_map.SAMPLE_IDX_OFFSET_LSB = 0
        ol.adc_to_udp_stream_C.register_map.SAMPLE_IDX_OFFSET_MSB = 0
    if 'D' in channels:
        ol.adc_to_udp_stream_D.register_map.SAMPLE_IDX_OFFSET_LSB = 0
        ol.adc_to_udp_stream_D.register_map.SAMPLE_IDX_OFFSET_MSB = 0
    set_channel_ctrl(ol, channels, Ctrl.CAPTURE)

def capture_next_pps(ol, channels, sample_rate):
    # Start in RESET
    set_channel_ctrl(ol, channels, Ctrl.RESET)

    # Wait for beginning of second to initiate capture
    current_time = time.time()
    start_time = current_time
    while((current_time - int(current_time)) > .5):
        time.sleep(.1)
        current_time = time.time()

    # Delay 100ms for PPS sync
    time.sleep(.1)
    current_time = time.time()

    # Capture on next PPS edge
    set_channel_ctrl(ol, channels, Ctrl.CAPTURE_NEXT_PPS)

    # Set start time in UDP Header
    current_time_s = int(current_time) + 1          # Stream starts PPS edge
    samples_since_epoch = int(current_time_s * sample_rate) # ((ADC_SAMPLE_FREQUENCY * 1e6)/ ADC_DECIMATION))
    samples_since_epoch_lsb = samples_since_epoch & 0xFFFFFFFF
    samples_since_epoch_msb = samples_since_epoch >> 32
    if 'A' in channels:
        ol.adc_to_udp_stream_A.register_map.SAMPLE_IDX_OFFSET_LSB = samples_since_epoch_lsb
        ol.adc_to_udp_stream_A.register_map.SAMPLE_IDX_OFFSET_MSB = samples_since_epoch_msb
    if 'B' in channels:
        ol.adc_to_udp_stream_B.register_map.SAMPLE_IDX_OFFSET_LSB = samples_since_epoch_lsb
        ol.adc_to_udp_stream_B.register_map.SAMPLE_IDX_OFFSET_MSB = samples_since_epoch_msb
    if 'C' in channels:
        ol.adc_to_udp_stream_C.register_map.SAMPLE_IDX_OFFSET_LSB = samples_since_epoch_lsb
        ol.adc_to_udp_stream_C.register_map.SAMPLE_IDX_OFFSET_MSB = samples_since_epoch_msb
    if 'D' in channels:
        ol.adc_to_udp_stream_D.register_map.SAMPLE_IDX_OFFSET_LSB = samples_since_epoch_lsb
        ol.adc_to_udp_stream_D.register_map.SAMPLE_IDX_OFFSET_MSB = samples_since_epoch_msb

    logging.info(f"Capture initiated at: {BLUE}{start_time}{RESET}")
    while(int(ol.adc_to_udp_stream_A.register_map.PPS_COUNTER) < 1
          and int(ol.adc_to_udp_stream_B.register_map.PPS_COUNTER) < 1
          and int(ol.adc_to_udp_stream_C.register_map.PPS_COUNTER) < 1
          and int(ol.adc_to_udp_stream_D.register_map.PPS_COUNTER) < 1):
        time.sleep(.01)

    logging.info(f"{GREEN}PPS Trigger received{RESET}")
    logging.info(f"Capture started at:   {BLUE}{current_time_s}{RESET} sample_offset: {BLUE}{samples_since_epoch}{RESET}")

def set_channel_ctrl(ol, channels, ctrl):
    logging.info(f"Set CTRL on {channels} to {ctrl}")
    if 'A' in channels:
        ol.adc_to_udp_stream_A.register_map.CTRL = ctrl.value # Set A control reg to 0x11
    if 'B' in channels:
        ol.adc_to_udp_stream_B.register_map.CTRL = ctrl.value # Set B control reg to 0x11
    if 'C' in channels:
        ol.adc_to_udp_stream_C.register_map.CTRL = ctrl.value # Set C control reg to 0x11
    if 'D' in channels:
        ol.adc_to_udp_stream_D.register_map.CTRL = ctrl.value # Set D control reg to 0x11

def zmq_cmd_handler(ol, channels, message, sample_rate):
    print("") # Newline
    logging.info(f"Received: {message}")

    if not message.startswith("cmd "):
        logging.warning("Invalid command format")
        return

    parts = message[4:].split()
    if not parts:
        logging.warning("No command specified")
        return

    command = parts[0]
    args = parts[1:]

    if (command == "reset"):
        set_channel_ctrl(ol, channels, Ctrl.RESET)
    elif (command == "capture"):
        capture_now(ol, channels)
    elif (command == "capture_next_pps"):
        capture_next_pps(ol, channels, sample_rate)
    elif (command == "set"):
        logging.info(f"Received command: {command} with args: {args}")
        if len(args) != 2:
            logging.warning(f"Invalid set command")
            return
        set_param = args[0]
        set_value = args[1]

        if (set_param == "freq_metadata"):
            set_freq_metadata(ol, channels, int(set_value))
        else:
            logging.warning(f"Invalid set command")

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
                        choices=all_channels, help='List of channels (A, B)',
                        default = 'A')
                        
    args = parser.parse_args()
    main(args)
