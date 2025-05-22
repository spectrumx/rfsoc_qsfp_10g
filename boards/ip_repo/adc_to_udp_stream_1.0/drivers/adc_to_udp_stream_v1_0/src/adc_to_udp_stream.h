
#ifndef ADC_TO_UDP_STREAM_H
#define ADC_TO_UDP_STREAM_H


/****************** Include Files ********************/
#include "xil_types.h"
#include "xstatus.h"

#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG0_OFFSET 0
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG1_OFFSET 4
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG2_OFFSET 8
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG3_OFFSET 12
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG4_OFFSET 16
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG5_OFFSET 20
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG6_OFFSET 24
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG7_OFFSET 28
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG8_OFFSET 32
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG9_OFFSET 36
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG10_OFFSET 40
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG11_OFFSET 44
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG12_OFFSET 48
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG13_OFFSET 52
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG14_OFFSET 56
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG15_OFFSET 60
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG16_OFFSET 64
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG17_OFFSET 68
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG18_OFFSET 72
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG19_OFFSET 76
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG20_OFFSET 80
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG21_OFFSET 84
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG22_OFFSET 88
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG23_OFFSET 92
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG24_OFFSET 96
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG25_OFFSET 100
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG26_OFFSET 104
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG27_OFFSET 108
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG28_OFFSET 112
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG29_OFFSET 116
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG30_OFFSET 120
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG31_OFFSET 124
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG32_OFFSET 128
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG33_OFFSET 132
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG34_OFFSET 136
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG35_OFFSET 140
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG36_OFFSET 144
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG37_OFFSET 148
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG38_OFFSET 152
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG39_OFFSET 156
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG40_OFFSET 160
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG41_OFFSET 164
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG42_OFFSET 168
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG43_OFFSET 172
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG44_OFFSET 176
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG45_OFFSET 180
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG46_OFFSET 184
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG47_OFFSET 188
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG48_OFFSET 192
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG49_OFFSET 196
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG50_OFFSET 200
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG51_OFFSET 204
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG52_OFFSET 208
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG53_OFFSET 212
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG54_OFFSET 216
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG55_OFFSET 220
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG56_OFFSET 224
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG57_OFFSET 228
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG58_OFFSET 232
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG59_OFFSET 236
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG60_OFFSET 240
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG61_OFFSET 244
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG62_OFFSET 248
#define ADC_TO_UDP_STREAM_S00_AXI_SLV_REG63_OFFSET 252


/**************************** Type Definitions *****************************/
/**
 *
 * Write a value to a ADC_TO_UDP_STREAM register. A 32 bit write is performed.
 * If the component is implemented in a smaller width, only the least
 * significant data is written.
 *
 * @param   BaseAddress is the base address of the ADC_TO_UDP_STREAMdevice.
 * @param   RegOffset is the register offset from the base to write to.
 * @param   Data is the data written to the register.
 *
 * @return  None.
 *
 * @note
 * C-style signature:
 * 	void ADC_TO_UDP_STREAM_mWriteReg(u32 BaseAddress, unsigned RegOffset, u32 Data)
 *
 */
#define ADC_TO_UDP_STREAM_mWriteReg(BaseAddress, RegOffset, Data) \
  	Xil_Out32((BaseAddress) + (RegOffset), (u32)(Data))

/**
 *
 * Read a value from a ADC_TO_UDP_STREAM register. A 32 bit read is performed.
 * If the component is implemented in a smaller width, only the least
 * significant data is read from the register. The most significant data
 * will be read as 0.
 *
 * @param   BaseAddress is the base address of the ADC_TO_UDP_STREAM device.
 * @param   RegOffset is the register offset from the base to write to.
 *
 * @return  Data is the data from the register.
 *
 * @note
 * C-style signature:
 * 	u32 ADC_TO_UDP_STREAM_mReadReg(u32 BaseAddress, unsigned RegOffset)
 *
 */
#define ADC_TO_UDP_STREAM_mReadReg(BaseAddress, RegOffset) \
    Xil_In32((BaseAddress) + (RegOffset))

/************************** Function Prototypes ****************************/
/**
 *
 * Run a self-test on the driver/device. Note this may be a destructive test if
 * resets of the device are performed.
 *
 * If the hardware system is not built correctly, this function may never
 * return to the caller.
 *
 * @param   baseaddr_p is the base address of the ADC_TO_UDP_STREAM instance to be worked on.
 *
 * @return
 *
 *    - XST_SUCCESS   if all self-test code passed
 *    - XST_FAILURE   if any self-test code failed
 *
 * @note    Caching must be turned off for this function to work.
 * @note    Self test may fail if data memory and device are not on the same bus.
 *
 */
XStatus ADC_TO_UDP_STREAM_Reg_SelfTest(void * baseaddr_p);

#endif // ADC_TO_UDP_STREAM_H
