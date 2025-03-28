__author__ = "David Northcote, Josh Goldsmith, Marius Siauciulis"

from pynq import Overlay
import os
import time
import xrfdc
import xrfclk
from . import networkLayer
from . import signal_generator
from . import fifo_control
from . import packet_generator

# "SAMPLE_FREQUENCY" : (DecimationFactor, XRFDC_FAB_CLK_DIVx)
fs2div = {
    '1024000000.0': (1,0),
    '512600000.0': (2,2),
    '256800000.0': (4,3),
    '128000000.0':  (8,4),
    '64000000.0':  (16,5)
}

class Overlay (Overlay):
    """Class for the RFSoC offload overlay
    """
    
    def __init__(self, bitfile_name=None, **kwargs):
        """Initialise the overlay and drivers.
        """

        # Generate default bitfile name
        if bitfile_name is None:
            this_dir = os.path.dirname(__file__)
            bitfile_name = os.path.join(this_dir, 'bitstream', 'rfsoc_offload.bit')
        else:
            if not os.path.isfile(bitfile_name):
                raise ValueError("Bitstream does not exist.")

        # Initialise Overlay class
        super().__init__(bitfile_name, **kwargs)
        
    def init_rf_clks(self, lmk_freq=245.76, lmx_freq=491.52):
        """Initialise the LMX and LMK clocks for RF-DC operation.
        """
        xrfclk.set_ref_clks(lmk_freq=lmk_freq, lmx_freq=lmx_freq)
        
    def initialise_adc(self, tile, block, pll_freq=491.52, fs=4915.2, fc=0.0):
        """Initialise an ADC tile and block in bypass mode.
        """
        self.rfdc.adc_tiles[tile].DynamicPLLConfig(1, pll_freq, fs)
        self.rfdc.adc_tiles[tile].blocks[block].NyquistZone = 1
        self.rfdc.adc_tiles[tile].blocks[block].MixerSettings = {
            'CoarseMixFreq':  xrfdc.COARSE_MIX_BYPASS,
            'EventSource':    xrfdc.EVNT_SRC_TILE,
            'FineMixerScale': xrfdc.MIXER_SCALE_1P0,
            'Freq':           fc,
            'MixerMode':      xrfdc.MIXER_MODE_R2C,
            'MixerType':      xrfdc.MIXER_TYPE_FINE,
            'PhaseOffset':    0.0
        }
        self.rfdc.adc_tiles[tile].blocks[block].UpdateEvent(xrfdc.EVENT_MIXER)
        self.rfdc.adc_tiles[tile].SetupFIFO(True)
        
    def initialise_dac(self, tile, block, pll_freq=491.52, fs=2457.60, fc=0.0):
        """Initialise a DAC tile and block in bypass mode.
        """
        self.rfdc.dac_tiles[tile].DynamicPLLConfig(1, pll_freq, fs)
        self.rfdc.dac_tiles[tile].blocks[block].NyquistZone = 1
        self.rfdc.dac_tiles[tile].blocks[block].MixerSettings['EventSource'] = xrfdc.EVNT_SRC_IMMEDIATE
        self.rfdc.dac_tiles[tile].SetupFIFO(True)

    def enable_udp(self, state):
        """ Enable (True) or Disable (False) the UDP packet generator
        """
        if(state): 
            # 128 * 64 bytes = 8192 bytes to be sent
            self.adc_packet_generator.packet_generator.packetsize = 128
            self.adc_packet_generator.packet_generator.enable()
        else:
            self.adc_packet_generator.packet_generator.disable()

    def set_decimation(self, tile, block, sample_rate):
        """ Set the sampling rate by changing decimation factor and FabClkDiv.
        """
        decimation_factor, fab_clk_div = fs2div[str(sample_rate)]
        self.enable_udp(False)
        self.rfdc.adc_tiles[tile].ShutDown()
        self.rfdc.adc_tiles[tile].FabClkOutDiv = fab_clk_div
        self.rfdc.adc_tiles[tile].blocks[block].DecimationFactor = decimation_factor
        self.rfdc.adc_tiles[tile].StartUp()
        self.enable_udp(True)
        return sample_rate

    def set_fc(self, tile, block, fc):
        """ Change the center frequency.
        """
        self.rfdc.adc_tiles[tile].blocks[block].MixerSettings['Freq'] = -fc
        self.rfdc.adc_tiles[tile].blocks[block].UpdateEvent(xrfdc.EVENT_MIXER)
        return fc

    def adc_select(self, adc_sel):
        # 0 = ADC B
        # 1 = ADC A
        self.adc_packet_generator.netlayer_switch.write(0x40, adc_sel)
        self.adc_packet_generator.netlayer_switch.write(0x00, 0x02)
