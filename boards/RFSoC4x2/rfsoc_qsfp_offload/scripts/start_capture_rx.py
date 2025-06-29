import os, sys
import time
import signal
import argparse
import logging
import termios
import tty
import xrfdc
import xrfclk
import zmq
from rfsoc_qsfp_offload.overlay import Overlay
from enum import Enum

ZMQ_PUB_SOCKET = "tcp://*:60201"  
ZMQ_SUB_SOCKET = "tcp://192.168.20.1:60200"
LOG_DIR = '/var/log/spectrumx'

ADC_SAMPLE_FREQUENCY = 1024     # MSps
ADC_DECIMATION = 16             # Default, not actively set
ADC_IF = 1090                   # MHz
ALL_CHANNELS = ['A', 'B', 'C', 'D']

GREEN = "\033[92m"
BLUE = "\033[94m"
RED = "\033[91m"
RESET = "\033[0m"

exit_flag = False               # Global for exit handler

class Ctrl(Enum):
    """
    Enum for control register state
    """
    CAPTURE = 0
    RESET = 1
    CAPTURE_NEXT_PPS = 3

class CaptureData:
    """
    Class to hold capture data parameters
    """
    def __init__(self):
        self.state = 'inactive'
        self.f_c_hz = float('nan')
        self.f_if_hz = float('nan')
        self.f_s = float('nan')
        self.channels = []
        self.pub_socket = None
        self.ol = None

def signal_handler(sig, frame):
    """
    Ctrl-C handler
    """
    global exit_flag

    logging.info('')
    logging.info('Exiting RF capture')
    exit_flag = True
    
def main(args):
    """
    Main function for the RX capture script

    Args:
        args (argparse.Namespace): Command-line arguments. 

    """
    global exit_flag

    # Configure logging
    os.makedirs(LOG_DIR, exist_ok=True)
    time_str = time.strftime("%Y%m%d_%H%M%S", time.localtime())
    log_filename = f"rfsoc_capture_{time_str}.log"
    log_filepath = os.path.join(LOG_DIR, log_filename)

    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        filename=log_filepath
    )

    # Add console handler to also log to terminal
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
    console_handler.setFormatter(formatter)
    logging.getLogger().addHandler(console_handler)

    logging.info(f"Starting RF capture on ADC Channel {BLUE}{args.channels}{RESET} at {BLUE}{args.freq:0.3f} MHz{RESET}") 

    # Initialize data struct
    data = CaptureData()
    data.f_if_hz = args.freq * 1e6

    # ZMQ context and sockets
    logging.info(f"ZMQ Publish to {ZMQ_PUB_SOCKET}")
    logging.info(f"ZMQ Subscribe to {ZMQ_SUB_SOCKET}")
    context = zmq.Context()

    sub_socket = context.socket(zmq.SUB)
    sub_socket.connect(ZMQ_SUB_SOCKET)
    sub_socket.setsockopt_string(zmq.SUBSCRIBE, "cmd") 

    poller = zmq.Poller()
    poller.register(sub_socket, zmq.POLLIN)

    data.pub_socket = context.socket(zmq.PUB)
    data.pub_socket.bind(ZMQ_PUB_SOCKET)

    # Initialize FPGA overlay
    logging.info("Initializing RFSoC 10G Overlay")
    data.ol = Overlay(ignore_version=True)
    time.sleep(5) # Wait for overlay to initialize

    # Disable all ADC UDP streams
    data.channels = ALL_CHANNELS
    set_channel_ctrl(Ctrl.RESET, data)

    # Select active channels
    data.channels = args.channels

    # Set reference clocks
    lmx_freq=491.52
    if args.internal_clock:
        # Config file for lmk_freq = 245.76 defaults to RFSoC VCO clock
        xrfclk.set_ref_clks(lmk_freq=245.76, lmx_freq=lmx_freq)
    else :
        # Config file for lmk_freq = 122.88 defaults to external clock reference
        xrfclk.set_ref_clks(lmk_freq=122.88, lmx_freq=lmx_freq)

    # Configure ADC
    adc_f_c = -1*data.f_if_hz           # User input
    adc_f_s = ADC_SAMPLE_FREQUENCY
    pll_freq = lmx_freq                 # MHz

    mixer_settings_block = {
            'CoarseMixFreq':  xrfdc.COARSE_MIX_BYPASS,
            'EventSource':    xrfdc.EVNT_SRC_TILE,
            'FineMixerScale': xrfdc.MIXER_SCALE_1P0,
            'Freq':           adc_f_c,
            'MixerMode':      xrfdc.MIXER_MODE_R2C,
            'MixerType':      xrfdc.MIXER_TYPE_FINE,
            'PhaseOffset':    0.0
            }

    # Configure all ADC channels to same f_c
    adc_tile_block = ((0,0), (0,1), (2,0), (2,1))
    mixer_blocks = [mixer_settings_block.copy(), mixer_settings_block.copy(), 
                   mixer_settings_block.copy(), mixer_settings_block.copy()]

    for (tile, block), mixer in zip(adc_tile_block, mixer_blocks):
        data.ol.rfdc.adc_tiles[tile].DynamicPLLConfig(1, pll_freq, adc_f_s)
        data.ol.rfdc.adc_tiles[tile].blocks[block].NyquistZone = 1
        data.ol.rfdc.adc_tiles[tile].blocks[block].MixerSettings = mixer
        data.ol.rfdc.adc_tiles[tile].blocks[block].UpdateEvent(xrfdc.EVENT_MIXER)
        data.ol.rfdc.adc_tiles[tile].SetupFIFO(True)

    logging.info(f"Starting UDP stream on: {BLUE}{data.channels}{RESET}")

    # Set center frequency
    set_freq_metadata(adc_f_c * 1e6, data)
    set_sample_rate((ADC_SAMPLE_FREQUENCY * 1e6)/ ADC_DECIMATION, data)

    # Set enable on next pps capture 
    if not args.reset:
        if not args.internal_clock:
            capture_next_pps(data)
        else:
            capture_now(data)

    pps_count_last = 0
    print("CTRL-C to exit")
    while(not exit_flag):
        # Check for incoming messages with 10ms timeout
        socks = dict(poller.poll(timeout=10))

        if sub_socket in socks:
            message = sub_socket.recv_string()
            zmq_cmd_handler(message, data)

        pps_count = max(
            int(data.ol.adc_to_udp_stream_A.register_map.PPS_COUNTER),
            int(data.ol.adc_to_udp_stream_B.register_map.PPS_COUNTER),
            int(data.ol.adc_to_udp_stream_C.register_map.PPS_COUNTER),
            int(data.ol.adc_to_udp_stream_D.register_map.PPS_COUNTER))
        if(pps_count > pps_count_last):
            print(f"\rElapsed capture time: {BLUE}{pps_count}{RESET}", end='', flush=True)

    logging.info("Stopping UDP stream")

    # Place all channels in reset
    data.channels = ALL_CHANNELS
    set_channel_ctrl(Ctrl.RESET, data)

def set_sample_rate(sample_rate, data):
    data.f_s = sample_rate
    sample_rate_raw = sample_rate * ADC_DECIMATION
    logging.info(f"Setting sample rate metadata to: {sample_rate_raw}")
    if 'A' in data.channels:
        data.ol.adc_to_udp_stream_A.register_map.SAMPLE_RATE_NUMERATOR_LSB = sample_rate_raw
    if 'B' in data.channels:
        data.ol.adc_to_udp_stream_B.register_map.SAMPLE_RATE_NUMERATOR_LSB = sample_rate_raw
    if 'C' in data.channels:
        data.ol.adc_to_udp_stream_C.register_map.SAMPLE_RATE_NUMERATOR_LSB = sample_rate_raw
    if 'D' in data.channels:
        data.ol.adc_to_udp_stream_D.register_map.SAMPLE_RATE_NUMERATOR_LSB = sample_rate_raw

def set_freq_metadata(f_c_hz, data):
    data.f_c_hz = f_c_hz
    logging.info(f"Setting frequency metadata to: {f_c_hz}")
    if 'A' in data.channels:
        data.ol.adc_to_udp_stream_A.register_map.FREQUENCY_IDX =  f_c_hz
    if 'B' in data.channels:
        data.ol.adc_to_udp_stream_B.register_map.FREQUENCY_IDX =  f_c_hz 
    if 'C' in data.channels:
        data.ol.adc_to_udp_stream_C.register_map.FREQUENCY_IDX =  f_c_hz
    if 'D' in data.channels:
        data.ol.adc_to_udp_stream_D.register_map.FREQUENCY_IDX =  f_c_hz 

def capture_now(data):
    set_channel_ctrl(Ctrl.RESET, data)
    if 'A' in data.channels:
        data.ol.adc_to_udp_stream_A.register_map.SAMPLE_IDX_OFFSET_LSB = 0
        data.ol.adc_to_udp_stream_A.register_map.SAMPLE_IDX_OFFSET_MSB = 0
    if 'B' in data.channels:
        data.ol.adc_to_udp_stream_B.register_map.SAMPLE_IDX_OFFSET_LSB = 0
        data.ol.adc_to_udp_stream_B.register_map.SAMPLE_IDX_OFFSET_MSB = 0
    if 'C' in data.channels:
        data.ol.adc_to_udp_stream_C.register_map.SAMPLE_IDX_OFFSET_LSB = 0
        data.ol.adc_to_udp_stream_C.register_map.SAMPLE_IDX_OFFSET_MSB = 0
    if 'D' in data.channels:
        data.ol.adc_to_udp_stream_D.register_map.SAMPLE_IDX_OFFSET_LSB = 0
        data.ol.adc_to_udp_stream_D.register_map.SAMPLE_IDX_OFFSET_MSB = 0
    set_channel_ctrl(Ctrl.CAPTURE, data)

def capture_next_pps(data):
    # Start in RESET
    set_channel_ctrl(Ctrl.RESET, data)

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
    set_channel_ctrl(Ctrl.CAPTURE_NEXT_PPS, data)

    # Set start time in UDP Header
    current_time_s = int(current_time) + 1                  # Stream starts PPS edge
    samples_since_epoch = int(current_time_s * data.f_s) 
    samples_since_epoch_lsb = samples_since_epoch & 0xFFFFFFFF
    samples_since_epoch_msb = samples_since_epoch >> 32
    if 'A' in data.channels:
        data.ol.adc_to_udp_stream_A.register_map.SAMPLE_IDX_OFFSET_LSB = samples_since_epoch_lsb
        data.ol.adc_to_udp_stream_A.register_map.SAMPLE_IDX_OFFSET_MSB = samples_since_epoch_msb
    if 'B' in data.channels:
        data.ol.adc_to_udp_stream_B.register_map.SAMPLE_IDX_OFFSET_LSB = samples_since_epoch_lsb
        data.ol.adc_to_udp_stream_B.register_map.SAMPLE_IDX_OFFSET_MSB = samples_since_epoch_msb
    if 'C' in data.channels:
        data.ol.adc_to_udp_stream_C.register_map.SAMPLE_IDX_OFFSET_LSB = samples_since_epoch_lsb
        data.ol.adc_to_udp_stream_C.register_map.SAMPLE_IDX_OFFSET_MSB = samples_since_epoch_msb
    if 'D' in data.channels:
        data.ol.adc_to_udp_stream_D.register_map.SAMPLE_IDX_OFFSET_LSB = samples_since_epoch_lsb
        data.ol.adc_to_udp_stream_D.register_map.SAMPLE_IDX_OFFSET_MSB = samples_since_epoch_msb

    logging.info(f"Capture initiated at: {BLUE}{start_time}{RESET}")
    while(int(data.ol.adc_to_udp_stream_A.register_map.PPS_COUNTER) < 1
          and int(data.ol.adc_to_udp_stream_B.register_map.PPS_COUNTER) < 1
          and int(data.ol.adc_to_udp_stream_C.register_map.PPS_COUNTER) < 1
          and int(data.ol.adc_to_udp_stream_D.register_map.PPS_COUNTER) < 1):
        time.sleep(.01)

    logging.info(f"{GREEN}PPS Trigger received{RESET}")
    logging.info(f"Capture started at:   {BLUE}{current_time_s}{RESET} sample_offset: {BLUE}{samples_since_epoch}{RESET}")

def set_channel_ctrl(ctrl, data):
    logging.info(f"Set CTRL on {data.channels} to {ctrl}")
    if 'A' in data.channels:
        data.ol.adc_to_udp_stream_A.register_map.CTRL = ctrl.value # Set A control reg to 0x11
    if 'B' in data.channels:
        data.ol.adc_to_udp_stream_B.register_map.CTRL = ctrl.value # Set B control reg to 0x11
    if 'C' in data.channels:
        data.ol.adc_to_udp_stream_C.register_map.CTRL = ctrl.value # Set C control reg to 0x11
    if 'D' in data.channels:
        data.ol.adc_to_udp_stream_D.register_map.CTRL = ctrl.value # Set D control reg to 0x11
    
    if (ctrl==Ctrl.CAPTURE
        or ctrl==Ctrl.CAPTURE_NEXT_PPS):
        data.state = 'active'
    else :
        data.state = 'inactive'

def zmq_cmd_handler(message, data):
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
        set_channel_ctrl(Ctrl.RESET, data)
    elif (command == "capture"):
        capture_now(data)
    elif (command == "capture_next_pps"):
        capture_next_pps(data)
    elif (command == "set"):
        logging.info(f"Received command: {command} with args: {args}")
        if len(args) != 2:
            logging.warning(f"Invalid set command")
            return
        set_param = args[0]
        set_value = args[1]

        if (set_param == "freq_metadata"):
            set_freq_metadata(int(set_value), data)
        else:
            logging.warning(f"Invalid set command")
    elif (command == "get"):
        if len(args) < 1:
            logging.warning(f"Invalid get command")
            return
        get_param = args[0]

        if (get_param == "tlm"):
            logging.info("Sending telemetry")
            tlm_str = f"tlm {data.state},"
            tlm_str += f"{data.f_c_hz},"
            tlm_str += f"{data.f_if_hz},"
            tlm_str += f"{data.f_s},"
            tlm_str += f"{data.channels}"
            data.pub_socket.send_string(tlm_str)
    elif (command == "help"):
        help_str = "Commands: \n"
        help_str += "  help\n"
        help_str += "  reset\n"
        help_str += "  capture\n"
        help_str += "  capture_next_pps\n"
        help_str += "  set\n"
        help_str += "    freq_metadata <freq_hz>\n"
        help_str += "  get\n"
        help_str += "    tlm\n"
        help_str += "  quit"
        data.pub_socket.send_string(help_str)
    elif (command == "quit"):
        global exit_flag
        exit_flag = True

if __name__ == "__main__":
    # CTRL-C handler
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
    parser.add_argument('-f', '--freq',type=float,help='Intermediate frequency (MHz.) Also center frequency if external tuner is not used.',
                        default = ADC_IF)
    parser.add_argument('-c', '--channels',type=str,nargs='*',
                        choices=ALL_CHANNELS, help='Channels to capture',
                        default = 'A')
    parser.add_argument('-r', '--reset', action='store_true', 
                        help='Hold capture in reset on start')
    parser.add_argument('-i','--internal_clock', action='store_true', 
                        help='Disable external clock and use internal VCO')
    args = parser.parse_args()
    main(args)
