///////////////////////////////////////////////////////////////////////////////
// adc_to_udp_stream_v1_0.v
//
// Convert 64-bit I/Q stream from ADC block to UDP Packets 
// on a 64-bit AXIS Bus
//
//  Assumes constant stream from 64-bit input
//
// Expected Packet header
//   struct RfPktHeader {
//     uint64_t sample_idx; 
//     uint64_t sample_rate_numerator;
//     uint64_t sample_rate_denominator;
//     uint32_t frequency_idx;
//     uint32_t num_subchannels;
//     uint32_t pkt_samples;
//     uint16_t bits_per_int;
//     unsigned is_complex : 1;
//     unsigned reserved0 : 7;
//     uint8_t samples_per_adc_clock;
//     uint64_t first_sample_adc_clock;
//     uint64_t pps_adc_clock;
//     uint64_t reserved4;
//   } __attribute__((__packed__)); 
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

module adc_to_udp_stream_v1_0 #
(
    // Parameters of Axi Slave Bus Interface S00_AXI
    parameter integer C_S00_AXI_DATA_WIDTH	= 32,
    parameter integer C_S00_AXI_ADDR_WIDTH	= 7,

    // Parameters of Input AXIS Slave Bus Interface S01_AXIS
    parameter integer C_S01_AXIS_TDATA_WIDTH = 64, 

    // Parameters of Output AXIS Master Bus Interface M00_AXIS
    parameter integer C_M00_AXIS_TDATA_WIDTH = 64,
    parameter integer C_M00_AXIS_TKEEP_WIDTH = 8,

    // Default port
    parameter integer UDP_PORT = 60133
)
(
    // Ports of Axi Slave Bus Interface S00_AXI
    input wire  s00_axi_aclk,
    input wire  s00_axi_aresetn,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
    input wire [2 : 0] s00_axi_awprot,
    input wire  s00_axi_awvalid,
    output wire  s00_axi_awready,
    input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
    input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
    input wire  s00_axi_wvalid,
    output wire  s00_axi_wready,
    output wire [1 : 0] s00_axi_bresp,
    output wire  s00_axi_bvalid,
    input wire  s00_axi_bready,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
    input wire [2 : 0] s00_axi_arprot,
    input wire  s00_axi_arvalid,
    output wire  s00_axi_arready,
    output reg [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
    output wire [1 : 0] s00_axi_rresp,
    output wire  s00_axi_rvalid,
    input wire  s00_axi_rready,

    // Ports of AXIS Slave Bus Interface S01_AXIS
    input wire s01_axis_aclk,
    input wire s01_axis_aresetn,
    input wire s01_axis_tvalid,
    input wire [C_S01_AXIS_TDATA_WIDTH-1 : 0] s01_axis_tdata,
    output wire s01_axis_tready,

    // Ports of AXIS Master Bus Interface M00_AXIS
    input wire m00_axis_aclk,
    input wire m00_axis_aresetn,
    output wire m00_axis_tvalid,
    output wire [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata,
    output wire [C_M00_AXIS_TKEEP_WIDTH-1 : 0] m00_axis_tkeep,
    output wire m00_axis_tuser,
    output wire m00_axis_tlast,
    input wire m00_axis_tready,

    // ADC Clock
    input wire pps_comp
);

    // Local params
    localparam integer RADIO_HEADER_BYTES = 64;
    localparam integer PAYLOAD_WORDS = 4096;                                // Payload length (in 16-bit words)
    localparam integer UDP_HEADER_LENGTH = 8 + (PAYLOAD_WORDS * 2) + RADIO_HEADER_BYTES; 
    localparam integer IP_HEADER_LENGTH  = 20 + UDP_HEADER_LENGTH;          // 20 bytes (IP header) + UDP length
    localparam integer TOTAL_HEADER_LENGTH = 14 + IP_HEADER_LENGTH;         // 14 bytes (Ethernet header) + IP length

    localparam integer HEADER_STATE = (RADIO_HEADER_BYTES / 8) + 6;         // States to tx (words + headers)
    localparam integer FINAL_STATE = (PAYLOAD_WORDS / 4) + HEADER_STATE;    // States to tx (words + headers)

    localparam integer WORDS_PER_AXIS = C_S01_AXIS_TDATA_WIDTH / 16;        // 16-bit words
    localparam integer AXIS_PER_BUFFER = PAYLOAD_WORDS / WORDS_PER_AXIS;    // Ping-pong buffer size

    localparam integer FIFO_LENGTH = 2048;                                  // Longer than required length (power of 2)
    localparam integer FIFO_BUFFER = FIFO_LENGTH - (PAYLOAD_WORDS/4);
    localparam integer FIFO_READ_DELAY = 2;

    // Ping-pong buffer 
    wire buffer_select_s01;
    wire fifo_0_write_en_s01;
    wire fifo_1_write_en_s01;
    wire fifo_0_read_en;
    wire fifo_1_read_en;

    // Define the UDP packet 
    reg [7:0] udp_packet_int[0:41];             // Ethernet frame, IP header, UDP header
    reg [C_M00_AXIS_TDATA_WIDTH-1:0] udp_packet[0:FINAL_STATE];       // 22 words for 64-bit chunks

    // Ethernet Header
    reg [7:0] eth_dst_mac[5:0];                 // Destination MAC address (6 bytes)
    reg [7:0] eth_src_mac[5:0];                 // Source MAC address (6 bytes)
    reg [7:0] eth_type[1:0];                    // EtherType (e.g., 0x0800 for IPv4)

    // Initial IP Header Parts 
    reg [15:0] ip_header_length;
    reg [15:0] udp_header_length;
    reg [7:0] ip_header[0:19];                  // Array to store 8-bit words of IP header
    reg [7:0] udp_header[0:7];                  // Array to store 8-bit words of UDP header
    reg [31:0] sum;                             // IP Checksum
    reg [15:0] word;                            // 16-bit word for summing
    reg [7:0] eth_dst_mac_lsb[3:0];             // Temp storage for Destination MAC LSB
    reg start_udp_header;
    reg in_udp_header;
    wire update_packet_s01;

    // Radio packet header
    wire [7:0] radio_header[RADIO_HEADER_BYTES-1:0];     // Radio packet header (see comment at top of file) 
    reg [63:0] sample_idx;                      // Index of sample
    reg [63:0] sample_rate_numerator;           // Sample rate numerator
    reg [63:0] sample_rate_denominator;         // Sample rate denominator
    reg [31:0] frequency_idx;                   // Frequency index
    reg [31:0] num_subchannels;                 // Number of subchannels in packet
    reg [31:0] pkt_samples;                     // Number of samples in packet
    reg [15:0] bits_per_int;                    // Size of sample in bits
    reg [7:0] is_complex;                       // Is data complex?
    reg [7:0] samples_per_adc_clock;            // Samples per adc clock
    reg [63:0] pps_clock_count;                 // Clock cycle count of last PPS rising-edge
    reg [63:0] write_en_clock_count;            // Clock cycle count of first sample in packet

    reg [63:0] packet_idx;                      // 64-bit counter for sent packets
    reg [63:0] sample_idx_offset;               // 64-bit offset for sample index

    // State machine signals
    reg [15:0] packet_state;                    // Current state/index (0 to 5 to traverse the packet header)
    wire start_payload;
    wire in_payload;

    // AXI bus signals
    reg [C_M00_AXIS_TDATA_WIDTH-1:0] udp_packet_axis_data;           
    reg [C_M00_AXIS_TDATA_WIDTH-1:0] fifo_out_data_prev;           

    // Timer to trigger packet transmission every 100ms
    reg [31:0] received_counter_s01;                // 32-bit counter for received AXIS transactions
    reg [31:0] full_buffer_counter;             // 32-bit counter for full buffers

    //////////////////////////////////////////////////////////////////////////
    // Sync user_reset to all clock domains
    //////////////////////////////////////////////////////////////////////////

    reg user_reset_s00;                            // User reset
    wire user_reset_s01;
    wire user_reset_m00;

    initial begin
        user_reset_s00 = 1'b1;
    end

    // Two stage reset sync for S01 clock domain
    reset_clock_sync user_reset_s01_sync (
        .clk1_in(s01_axis_aclk),
        .reset_clk0(user_reset_s00),
        .reset_clk1(user_reset_s01)
    );

    // Two stage reset sync for M00 clock domain
    reset_clock_sync user_reset_m00_sync (
        .clk1_in(m00_axis_aclk),
        .reset_clk0(user_reset_s00),
        .reset_clk1(user_reset_m00)
    );

    //////////////////////////////////////////////////////////////////////////
    // Count rising edges of ADC clock when PPS goes high
    //////////////////////////////////////////////////////////////////////////

    wire [63:0] adc_clk_count;
    reg [31:0] pps_count;                       // Count PPS rising edges
    reg pps_detect_s01;                  // S01
    reg enable_next_pps_s00;                    // S00 clock domain
    wire enable_next_pps_s01;                   // S01 clock domain
    reg [1:0] sync_enable_next_pps_s01;
    reg pps_comp_s01;
    reg [63:0] fifo_0_write_en_s01_clock_count;
    reg [63:0] fifo_1_write_en_s01_clock_count;

    initial begin
        pps_count = 32'h0;
        pps_detect_s01 = 1'b0;
        enable_next_pps_s00 = 1'b0;
        pps_comp_s01 = 1'b0;
        fifo_0_write_en_s01_clock_count = 64'b0;
        fifo_1_write_en_s01_clock_count = 64'b0;
    end

    // Sync enable next PPS request from S00 bus
    reset_clock_sync enable_next_pps_sync (
        .clk1_in(s01_axis_aclk),
        .reset_clk0(enable_next_pps_s00),
        .reset_clk1(enable_next_pps_s01)
    );

    // ADC clock counter
    rising_edge_counter #(
        .COUNTER_WIDTH(64)
    ) adc_clk_counter_inst (
        .clk_in(s01_axis_aclk),
        .resetn(s01_axis_aresetn),
        .edge_count(adc_clk_count)
    );

    // PPS counter and PPS clock cycle counter
    always @(posedge s01_axis_aclk or negedge s01_axis_aresetn) begin
        if(!s01_axis_aresetn) begin
            pps_comp_s01 = 1'b0;
            pps_count <= 32'h0;
            pps_clock_count <= 64'h0;
            pps_detect_s01 <= 1'b0;
        end else begin
            // Reset PPS on user reset if enable next pps is not set
            if (user_reset_s01 && !enable_next_pps_s01) begin
                pps_count <= 32'h0;
                pps_clock_count <= 64'h0;
                pps_detect_s01 <= 1'b0;
            // Reset PPS detect if enable_next_pps is disabled
            end else if (pps_detect_s01 && !enable_next_pps_s01) begin
                pps_detect_s01 <= 1'b0;
            // Check for rising edge of PPS
            end else if (pps_comp && !pps_comp_s01) begin
                pps_count <= pps_count + 1;
                pps_clock_count <= adc_clk_count;

                // Sync enable next pps signal
                if(!pps_detect_s01 && enable_next_pps_s01) begin
                    pps_detect_s01 <= 1'b1;
                end
            end

            // Sync PPS to ADC clock
            pps_comp_s01 <= pps_comp;
        end
    end

    // Capture adc_clk_count when write select transitions high 
    always @(posedge fifo_0_write_en_s01 or negedge s01_axis_aresetn) begin
        if (!s01_axis_aresetn) begin
            fifo_0_write_en_s01_clock_count <= 64'h0;
        end else begin
            fifo_0_write_en_s01_clock_count <= adc_clk_count; // Capture on rising edge 
        end
    end

    always @(posedge fifo_1_write_en_s01 or negedge s01_axis_aresetn) begin
        if (!s01_axis_aresetn) begin
            fifo_1_write_en_s01_clock_count <= 64'h0;
        end else begin
            fifo_1_write_en_s01_clock_count <= adc_clk_count; // Capture on rising edge 
        end
    end

    // Select the active write enable clock count
    always @(*) begin
        if (buffer_select_s01)
            write_en_clock_count = fifo_0_write_en_s01_clock_count;
        else
            write_en_clock_count = fifo_1_write_en_s01_clock_count;
    end

    // Update sample index
    always @(*) begin
        sample_idx = packet_idx * (PAYLOAD_WORDS / 2) + sample_idx_offset;
    end

    //////////////////////////////////////////////////////////////////////////
    // Ping-pong buffer for incoming ADC samples
    // Use block ram FIFO
    //////////////////////////////////////////////////////////////////////////

    // FIFO
    reg fifo_0_reset;
    reg fifo_1_reset;
    reg fifo_0_full_reg_s01;
    reg fifo_1_full_reg_s01;
    reg fifo_0_full_delay_s01;
    reg fifo_1_full_delay_s01;
    reg fifo_0_read_en_latched;
    reg fifo_1_read_en_latched;
    reg fifo_0_rst_busy_latched_s01;
    reg fifo_1_rst_busy_latched_s01;
    reg fifo_0_empty_latched;
    reg fifo_1_empty_latched;

    wire [C_M00_AXIS_TDATA_WIDTH-1:0] fifo_0_out_data;
    wire [C_M00_AXIS_TDATA_WIDTH-1:0] fifo_1_out_data;
    wire [11:0] fifo_0_wr_count;
    wire [11:0] fifo_1_wr_count;
    wire [11:0] fifo_0_rd_count;
    wire [11:0] fifo_1_rd_count;
    wire fifo_0_wr_rst_busy;
    wire fifo_0_rd_rst_busy;
    wire fifo_1_wr_rst_busy;
    wire fifo_1_rd_rst_busy;

    wire fifo_0_full_s01;
    wire fifo_1_full_s01;
    wire fifo_0_empty;
    wire fifo_1_empty;
    wire fifo_0_rst_busy_s01;
    wire fifo_1_rst_busy_s01;
    wire fifo_0_full_trigger_s01;
    wire fifo_1_full_trigger_s01;
    wire fifo_0_rst_combined_s01;
    wire fifo_1_rst_combined_s01;
    wire capture_enable_s01;

    initial begin
        fifo_0_empty_latched = 1'b0;
        fifo_1_empty_latched = 1'b0;
    end

    always @(posedge s01_axis_aclk or negedge s01_axis_aresetn) begin
        if (!s01_axis_aresetn || user_reset_s01) begin
            received_counter_s01 <= 0;
            fifo_0_rst_busy_latched_s01 <= 0;
            fifo_1_rst_busy_latched_s01 <= 0;
            fifo_0_reset <= 1;
            fifo_1_reset <= 1;
        end else begin
            // Write data to the appropriate buffer
            // Increment counter
            if (s01_axis_tvalid) begin
                received_counter_s01 <= received_counter_s01 + 1;
            end

            // Latch reset busy to delay extra cycle
            fifo_0_rst_busy_latched_s01 <= fifo_0_rst_busy_s01;
            fifo_1_rst_busy_latched_s01 <= fifo_1_rst_busy_s01;

            fifo_0_empty_latched <= fifo_0_empty;
            fifo_1_empty_latched <= fifo_1_empty;

            if (!fifo_0_empty_latched && fifo_0_empty) begin
                fifo_0_reset <= 1;
            end else if(fifo_0_reset) begin
                fifo_0_reset <= 0;
            end

            if (!fifo_1_empty_latched && fifo_1_empty) begin
                fifo_1_reset <= 1;
            end else if(fifo_1_reset) begin
                fifo_1_reset <= 0;
            end
        end
    end

    // When full select other buffer
    assign buffer_select_s01 = fifo_0_full_s01 | fifo_0_full_reg_s01;
    assign fifo_0_rst_busy_s01 = fifo_0_wr_rst_busy || fifo_0_rd_rst_busy;
    assign fifo_1_rst_busy_s01 = fifo_1_wr_rst_busy || fifo_1_rd_rst_busy;
    assign fifo_0_rst_combined_s01 = fifo_0_rst_busy_s01 || fifo_0_rst_busy_latched_s01;
    assign fifo_1_rst_combined_s01 = fifo_1_rst_busy_s01 || fifo_1_rst_busy_latched_s01;

    assign capture_enable_s01 = !user_reset_s01 || pps_detect_s01; 
    assign fifo_0_write_en_s01 = s01_axis_tvalid && s01_axis_aresetn && capture_enable_s01 && !fifo_0_rst_combined_s01 && !buffer_select_s01;
    assign fifo_1_write_en_s01 = s01_axis_tvalid && s01_axis_aresetn && capture_enable_s01 && !fifo_1_rst_combined_s01 && buffer_select_s01;

    // Flag fifo full transition for a single cycle
    always @(posedge m00_axis_aclk) begin
        if (!m00_axis_aresetn || user_reset_m00) begin
            fifo_0_full_reg_s01 <= 1'b0;
            fifo_0_full_delay_s01 <= 1'b0;
            fifo_1_full_reg_s01 <= 1'b0;
            fifo_1_full_delay_s01 <= 1'b0;
            full_buffer_counter <= 1'b0;
        end else begin
            if(fifo_0_full_s01) begin
                fifo_0_full_reg_s01 <= 1'b1;
                full_buffer_counter <= full_buffer_counter + 1;
                if (!fifo_1_full_s01) begin
                    fifo_1_full_reg_s01 <= 1'b0;
                end
            end
            if(fifo_1_full_s01) begin
                fifo_1_full_reg_s01 <= 1'b1;
                full_buffer_counter <= full_buffer_counter + 1;
                if (!fifo_0_full_s01) begin
                    fifo_0_full_reg_s01 <= 1'b0;
                end
            end

            fifo_0_full_delay_s01 <= fifo_0_full_reg_s01;
            fifo_1_full_delay_s01 <= fifo_1_full_reg_s01;
        end
    end

    assign fifo_0_full_trigger_s01 = fifo_0_full_reg_s01 && !fifo_0_full_delay_s01;
    assign fifo_1_full_trigger_s01 = fifo_1_full_reg_s01 && !fifo_1_full_delay_s01;
    assign update_packet_s01 = fifo_0_full_trigger_s01 || fifo_1_full_trigger_s01;

    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("block"),    // Use BRAM
        .ECC_MODE("no_ecc"),
        .FIFO_WRITE_DEPTH(FIFO_LENGTH),
        .WRITE_DATA_WIDTH(C_S01_AXIS_TDATA_WIDTH),
        .READ_DATA_WIDTH(C_M00_AXIS_TDATA_WIDTH),
        .WR_DATA_COUNT_WIDTH(12),
        .RD_DATA_COUNT_WIDTH(12),
        .PROG_FULL_THRESH(FIFO_LENGTH-FIFO_BUFFER),
        .PROG_EMPTY_THRESH(3)
    ) fifo_0_inst (
        .rst(fifo_0_reset),
        .sleep(1'b0),
        .injectdbiterr(1'b0),
        .injectsbiterr(1'b0),

        // Write side
        .wr_clk(s01_axis_aclk),
        .wr_en(fifo_0_write_en_s01),
        .din(s01_axis_tdata),
        .prog_full(fifo_0_full_s01),
        .wr_data_count(fifo_0_wr_count),
        .wr_rst_busy(fifo_0_wr_rst_busy),

        // Read side
        .rd_clk(m00_axis_aclk),
        .rd_en(fifo_0_read_en),
        .dout(fifo_0_out_data),
        .empty(fifo_0_empty),
        .rd_data_count(fifo_0_rd_count),
        .rd_rst_busy(fifo_0_rd_rst_busy)
    );

    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("block"),    // Use BRAM
        .ECC_MODE("no_ecc"),
        .FIFO_WRITE_DEPTH(FIFO_LENGTH),
        .WRITE_DATA_WIDTH(C_S01_AXIS_TDATA_WIDTH),
        .READ_DATA_WIDTH(C_M00_AXIS_TDATA_WIDTH),
        .WR_DATA_COUNT_WIDTH(12),
        .RD_DATA_COUNT_WIDTH(12),
        .PROG_FULL_THRESH(FIFO_LENGTH-FIFO_BUFFER),
        .PROG_EMPTY_THRESH(3)
    ) fifo_1_inst (
        .rst(fifo_1_reset),
        .sleep(1'b0),
        .injectdbiterr(1'b0),
        .injectsbiterr(1'b0),

        // Write side
        .wr_clk(s01_axis_aclk),
        .wr_en(fifo_1_write_en_s01),
        .din(s01_axis_tdata),
        .prog_full(fifo_1_full_s01),
        .wr_data_count(fifo_1_wr_count),
        .wr_rst_busy(fifo_1_wr_rst_busy),

        // Read side
        .rd_clk(m00_axis_aclk),
        .rd_en(fifo_1_read_en),
        .dout(fifo_1_out_data),
        .empty(fifo_1_empty),
        .rd_data_count(fifo_1_rd_count),
        .rd_rst_busy(fifo_1_rd_rst_busy)
    );

    //////////////////////////////////////////////////////////////////////////
    // Generate UDP Stream
    //////////////////////////////////////////////////////////////////////////

    // Initialize Ethernet frame, IP header, UDP header
    integer i;
    initial begin
        // Ethernet frame
        eth_dst_mac[0] = 8'hFF;
        eth_dst_mac[1] = 8'hFF;
        eth_dst_mac[2] = 8'hFF;
        eth_dst_mac[3] = 8'hFF;
        eth_dst_mac[4] = 8'hFF;
        eth_dst_mac[5] = 8'hFF; // Broadcast MAC address

        eth_src_mac[0] = 8'h00;
        eth_src_mac[1] = 8'h1A;
        eth_src_mac[2] = 8'h2B;
        eth_src_mac[3] = 8'h3C;
        eth_src_mac[4] = 8'h4D;
        eth_src_mac[5] = 8'h5E; // Source MAC address

        eth_type[0] = 8'h08;
        eth_type[1] = 8'h00;    // EtherType for IPv4

        // IP Header
        ip_header[0][7:0] = 8'h45;   // Version (4) + Header Length (5)
        ip_header[1][7:0] = 8'h00;
        ip_header[2][7:0] = IP_HEADER_LENGTH[15:8]; // Length MSB
        ip_header[3][7:0] = IP_HEADER_LENGTH[7:0];   // Length LSB
        ip_header[4][7:0] = 8'h00;   // Identification (0)
        ip_header[5][7:0] = 8'h01;
        ip_header[6][7:0] = 8'h40;   // Flags and Fragment Offset
        ip_header[7][7:0] = 8'h00;
        ip_header[8][7:0] = 8'hFF;   // TTL (255) and protocol (UDP)
        ip_header[9][7:0] = 8'h11;
        ip_header[10][7:0] = 8'hF1;   // Checksum placeholder
        ip_header[11][7:0] = 8'h9A;
        ip_header[12][7:0] = 8'hC0;   // Source IP (192.168.4.99)
        ip_header[13][7:0] = 8'hA8;
        ip_header[14][7:0] = 8'h04;
        ip_header[15][7:0] = 8'h63;
        ip_header[16][7:0] = 8'hC0;   // Destination IP (192.168.4.1) 
        ip_header[17][7:0] = 8'hA8;
        ip_header[18][7:0] = 8'h04;
        ip_header[19][7:0] = 8'h01;  

        // UDP Header
        udp_header[0][7:0] = UDP_PORT[15:8];
        udp_header[1][7:0] = UDP_PORT[7:0];
        udp_header[2][7:0] = UDP_PORT[15:8];
        udp_header[3][7:0] = UDP_PORT[7:0];
        udp_header[4][7:0] = UDP_HEADER_LENGTH[15:8];  // UDP Length MSB
        udp_header[5][7:0] = UDP_HEADER_LENGTH[7:0];   // UDP Length LSB
        udp_header[6][7:0] = 8'h00;   // Checksum placeholder 
        udp_header[7][7:0] = 8'h00;   // 

        // Radio Header fields
        packet_idx[63:0] = 64'd0;
        sample_idx[63:0] = 64'd0;
        sample_idx_offset[63:0] = 64'd0;
        sample_rate_numerator[63:0] = 64'd1228800000; // Default 1.2288Gsps
        sample_rate_denominator[63:0] = 64'd16; // Default 16x divisor
        frequency_idx[31:0] = 32'd0;
        num_subchannels[31:0] = 32'd0;
        pkt_samples[31:0] = PAYLOAD_WORDS / 2; 
        bits_per_int[15:0] = 16'd16;
        is_complex[7:0] = 8'd1;
        samples_per_adc_clock[7:0] = 8'd2;
        write_en_clock_count[63:0] = 64'd0;
        pps_clock_count[63:0] = 64'd0;

        // UDP Packet - initialize to 0
        for (i = 0; i < 42; i = i + 1) begin
            udp_packet_int[i] = 8'b0;
        end
        for (i = 0; i <= FINAL_STATE; i = i + 1) begin
            udp_packet[i] = 64'b0;
        end
    end

    // Assign Radio Header
    assign radio_header[0] = sample_idx[7:0];
    assign radio_header[1] = sample_idx[15:8];
    assign radio_header[2] = sample_idx[23:16];
    assign radio_header[3] = sample_idx[31:24];
    assign radio_header[4] = sample_idx[39:32];
    assign radio_header[5] = sample_idx[47:40];
    assign radio_header[6] = sample_idx[55:48];
    assign radio_header[7] = sample_idx[63:56];
    assign radio_header[8] = sample_rate_numerator[7:0];
    assign radio_header[9] = sample_rate_numerator[15:8];
    assign radio_header[10] = sample_rate_numerator[23:16];
    assign radio_header[11] = sample_rate_numerator[31:24];
    assign radio_header[12] = sample_rate_numerator[39:32];
    assign radio_header[13] = sample_rate_numerator[47:40];
    assign radio_header[14] = sample_rate_numerator[55:48];
    assign radio_header[15] = sample_rate_numerator[63:56];
    assign radio_header[16] = sample_rate_denominator[7:0];
    assign radio_header[17] = sample_rate_denominator[15:8];
    assign radio_header[18] = sample_rate_denominator[23:16];
    assign radio_header[19] = sample_rate_denominator[31:24];
    assign radio_header[20] = sample_rate_denominator[39:32];
    assign radio_header[21] = sample_rate_denominator[47:40];
    assign radio_header[22] = sample_rate_denominator[55:48];
    assign radio_header[23] = sample_rate_denominator[63:56];
    assign radio_header[24] = frequency_idx[7:0];
    assign radio_header[25] = frequency_idx[15:8];
    assign radio_header[26] = frequency_idx[23:16];
    assign radio_header[27] = frequency_idx[31:24];
    assign radio_header[28] = num_subchannels[7:0];
    assign radio_header[29] = num_subchannels[15:8];
    assign radio_header[30] = num_subchannels[23:16];
    assign radio_header[31] = num_subchannels[31:24];
    assign radio_header[32] = pkt_samples[7:0];
    assign radio_header[33] = pkt_samples[15:8];
    assign radio_header[34] = pkt_samples[23:16];
    assign radio_header[35] = pkt_samples[31:24];
    assign radio_header[36] = bits_per_int[7:0];
    assign radio_header[37] = bits_per_int[15:8];
    assign radio_header[38] = is_complex[7:0];
    assign radio_header[39] = 8'd0;
    assign radio_header[40] = write_en_clock_count[7:0];
    assign radio_header[41] = write_en_clock_count[15:8];
    assign radio_header[42] = write_en_clock_count[23:16];
    assign radio_header[43] = write_en_clock_count[31:24];
    assign radio_header[44] = write_en_clock_count[39:32];
    assign radio_header[45] = write_en_clock_count[47:40];
    assign radio_header[46] = write_en_clock_count[55:48];
    assign radio_header[47] = write_en_clock_count[63:56];
    assign radio_header[48] = pps_clock_count[7:0];
    assign radio_header[49] = pps_clock_count[15:8];
    assign radio_header[50] = pps_clock_count[23:16];
    assign radio_header[51] = pps_clock_count[31:24];
    assign radio_header[52] = pps_clock_count[39:32];
    assign radio_header[53] = pps_clock_count[47:40];
    assign radio_header[54] = pps_clock_count[55:48];
    assign radio_header[55] = pps_clock_count[63:56];
    assign radio_header[56] = 8'd0;
    assign radio_header[57] = 8'd0;
    assign radio_header[58] = 8'd0;
    assign radio_header[59] = 8'd0;
    assign radio_header[60] = 8'd0;
    assign radio_header[61] = 8'd0;
    assign radio_header[62] = 8'd0;
    assign radio_header[63] = 8'd0;

    // Calculate IP Checksum
    always @(posedge m00_axis_aclk) begin
        // Reassign static packet on reset
        if (!m00_axis_aresetn || user_reset_m00 || (update_packet_s01 == 1'b1)) begin
            sum = 32'b0;
            ip_header[10] = 8'h0;
            ip_header[11] = 8'h0;
        
            // Sum the IP header in 16-bit words
            for (i = 0; i < 20; i = i + 2) begin
                // Concatenate two consecutive bytes to form a 16-bit word
                word = {ip_header[i], ip_header[i+1]}; // word = ip_header[i+1] << 8 | ip_header[i]
                sum = sum + word;
            end
            
            sum = sum + (sum >> 16);  // Add upper 16 bits to lower 16 bits
            sum = ~sum[15:0];  // Take the lower 16 bits and invert them

            // Store the result back in the IP header
            ip_header[10] = sum[15:8];  // Upper 8 bits
            ip_header[11] = sum[7:0];   // Lower 8 bits
        end
    end

    // Assign Ethernet frame, IP header, UDP header, and payload to output
    always @(posedge m00_axis_aclk) begin
        // Reassign static packet on reset or update
        // Update is triggered when sending a new packet
        if (!m00_axis_aresetn || user_reset_m00 || (update_packet_s01 == 1'b1)) begin
            // Ethernet Header
            udp_packet_int[0] <= eth_dst_mac[0];
            udp_packet_int[1] <= eth_dst_mac[1];
            udp_packet_int[2] <= eth_dst_mac[2];
            udp_packet_int[3] <= eth_dst_mac[3];
            udp_packet_int[4] <= eth_dst_mac[4];
            udp_packet_int[5] <= eth_dst_mac[5];

            udp_packet_int[6] <= eth_src_mac[0];
            udp_packet_int[7] <= eth_src_mac[1];
            udp_packet_int[8] <= eth_src_mac[2];
            udp_packet_int[9] <= eth_src_mac[3];
            udp_packet_int[10] <= eth_src_mac[4];
            udp_packet_int[11] <= eth_src_mac[5];

            udp_packet_int[12] <= eth_type[0];
            udp_packet_int[13] <= eth_type[1];

            // IP Header
            udp_packet_int[14] <= ip_header[0];
            udp_packet_int[15] <= ip_header[1];
            udp_packet_int[16] <= ip_header[2];
            udp_packet_int[17] <= ip_header[3];
            udp_packet_int[18] <= ip_header[4];
            udp_packet_int[19] <= ip_header[5];
            udp_packet_int[20] <= ip_header[6];
            udp_packet_int[21] <= ip_header[7];
            udp_packet_int[22] <= ip_header[8];
            udp_packet_int[23] <= ip_header[9];
            udp_packet_int[24] <= ip_header[10];
            udp_packet_int[25] <= ip_header[11];
            udp_packet_int[26] <= ip_header[12];
            udp_packet_int[27] <= ip_header[13];
            udp_packet_int[28] <= ip_header[14];
            udp_packet_int[29] <= ip_header[15];
            udp_packet_int[30] <= ip_header[16];
            udp_packet_int[31] <= ip_header[17];
            udp_packet_int[32] <= ip_header[18];
            udp_packet_int[33] <= ip_header[19];

            // UDP Header
            udp_packet_int[34] <= udp_header[0];
            udp_packet_int[35] <= udp_header[1];
            udp_packet_int[36] <= udp_header[2];
            udp_packet_int[37] <= udp_header[3];
            udp_packet_int[38] <= udp_header[4];
            udp_packet_int[39] <= udp_header[5];
            udp_packet_int[40] <= udp_header[6];
            udp_packet_int[41] <= udp_header[7];

            // Assign 64-bit udp packet
            // Assumes payload is a least 4 words long
            udp_packet[0][63:0] <= {udp_packet_int[7], udp_packet_int[6], udp_packet_int[5], udp_packet_int[4], udp_packet_int[3], udp_packet_int[2], udp_packet_int[1], udp_packet_int[0]};
            udp_packet[1][63:0] <= {udp_packet_int[15], udp_packet_int[14], udp_packet_int[13], udp_packet_int[12], udp_packet_int[11], udp_packet_int[10], udp_packet_int[9], udp_packet_int[8]};
            udp_packet[2][63:0] <= {udp_packet_int[23], udp_packet_int[22], udp_packet_int[21], udp_packet_int[20], udp_packet_int[19], udp_packet_int[18], udp_packet_int[17], udp_packet_int[16]};
            udp_packet[3][63:0] <= {udp_packet_int[31], udp_packet_int[30], udp_packet_int[29], udp_packet_int[28], udp_packet_int[27], udp_packet_int[26], udp_packet_int[25], udp_packet_int[24]};
            udp_packet[4][63:0] <= {udp_packet_int[39], udp_packet_int[38], udp_packet_int[37], udp_packet_int[36], udp_packet_int[35], udp_packet_int[34], udp_packet_int[33], udp_packet_int[32]};

            // Assign radio packet
            udp_packet[5][63:0] <= {radio_header[5], radio_header[4],radio_header[3], radio_header[2], radio_header[1], radio_header[0], udp_packet_int[41], udp_packet_int[40]};
            udp_packet[6][63:0] <= {radio_header[13], radio_header[12], radio_header[11], radio_header[10],radio_header[9], radio_header[8], radio_header[7], radio_header[6]};
            udp_packet[7][63:0] <= {radio_header[21], radio_header[20], radio_header[19], radio_header[18], radio_header[17], radio_header[16], radio_header[15], radio_header[14]};
            udp_packet[8][63:0] <= {radio_header[29], radio_header[28], radio_header[27], radio_header[26], radio_header[25], radio_header[24], radio_header[23], radio_header[22]};
            udp_packet[9][63:0] <= {radio_header[37], radio_header[36], radio_header[35], radio_header[34], radio_header[33], radio_header[32], radio_header[31], radio_header[30]};
            udp_packet[10][63:0] <= {radio_header[45], radio_header[44], radio_header[43], radio_header[42], radio_header[41], radio_header[40], radio_header[39], radio_header[38]};
            udp_packet[11][63:0] <= {radio_header[53], radio_header[52], radio_header[51], radio_header[50], radio_header[49], radio_header[48], radio_header[47], radio_header[46]};
            udp_packet[12][63:0] <= {radio_header[61], radio_header[60], radio_header[59], radio_header[58], radio_header[57], radio_header[56], radio_header[55], radio_header[54]};

            // Assign payload from input stream buffer
            // Align ADC data with next full AXIS transacation
            // Sequence # + size
            udp_packet[13][63:0] <= {udp_packet_axis_data[63:16], radio_header[63], radio_header[62]};
        end
    end

    //////////////////////////////////////////////////////////////////////////
    // AXI4 Stream Output Data Bus
    //////////////////////////////////////////////////////////////////////////
    wire fifo_0_full_reg_m00;
    wire fifo_1_full_reg_m00;
    wire update_packet_m00;

    // Send UDP Packet over AXI bus
    assign start_payload = (packet_state >= (HEADER_STATE-FIFO_READ_DELAY)) && (packet_state <= FINAL_STATE);
    assign in_payload = (packet_state >= HEADER_STATE) && (packet_state <= FINAL_STATE);

    signal_clock_sync fifo_0_full_sync (
        .clk1_in(m00_axis_aclk),
        .signal_clk0(fifo_0_full_reg_s01),
        .signal_clk1(fifo_0_full_reg_m00)
    );

    signal_clock_sync fifo_1_full_sync (
        .clk1_in(m00_axis_aclk),
        .signal_clk0(fifo_1_full_reg_s01),
        .signal_clk1(fifo_1_full_reg_m00)
    );

    signal_clock_sync update_packet_sync (
        .clk1_in(m00_axis_aclk),
        .signal_clk0(update_packet_s01),
        .signal_clk1(update_packet_m00)
    );

    reg udp_packet_axis_valid;
    always @(posedge m00_axis_aclk or negedge m00_axis_aresetn) begin
        if (~m00_axis_aresetn || user_reset_m00) begin
            packet_idx <= 64'd0;
            packet_state <= 16'd0;
            fifo_0_read_en_latched <= 0;
            fifo_1_read_en_latched <= 0;
            start_udp_header <= 0;
            in_udp_header <= 0;
        end else begin
            // State machine to send the UDP packet over AXI4 Stream
            // start when input stream buffer is full
            if (update_packet_m00) begin
                // Reset state to start a new packet transmission
                packet_state <= 16'd0;
                start_udp_header <= 1'b1;
                packet_idx <= packet_idx + 1;       // Increment packets sent counter
            end else if (m00_axis_tready) begin
                if (start_udp_header) begin
                    // Wait one cycle for packet to update
                    in_udp_header <= 1'b1;
                end

                if (start_udp_header || in_udp_header) begin
                    // Switch from header to payload
                    if( packet_state >= (HEADER_STATE - 1)) begin
                        start_udp_header <= 1'b0;
                        in_udp_header <= 1'b0;
                    end
                end 

                // Increment packet state
                if (in_udp_header || in_payload) begin
                    if (packet_state <= FINAL_STATE + 1) begin
                        packet_state <= packet_state + 1;
                    end
                end
            end

            // update latched read enables
            if(start_payload) begin 
                // Buffer select = 0, read from Buffer 1 
                if (fifo_1_full_reg_m00) begin
                    fifo_1_read_en_latched <= 1;
                end

                // Buffer select = 1, read from Buffer 0 
                if (fifo_0_full_reg_m00) begin
                    fifo_0_read_en_latched <= 1;
                end
            end

            // Reset read enables when fifo is empty
            // of buffer is active for write
            if (fifo_0_empty || !buffer_select_s01) begin
                fifo_0_read_en_latched <= 0;
            end

            if (fifo_1_empty || buffer_select_s01) begin
                fifo_1_read_en_latched <= 0;
            end
        end

    end

    // Assign the latched values to the read enables
    // disable when tready is low
    assign fifo_0_read_en = fifo_0_read_en_latched && start_payload && m00_axis_tready && !fifo_0_rst_busy_s01;
    assign fifo_1_read_en = fifo_1_read_en_latched && start_payload && m00_axis_tready && !fifo_1_rst_busy_s01;

    always @(posedge m00_axis_aclk or negedge m00_axis_aresetn) begin
        if (~m00_axis_aresetn || user_reset_m00) begin
            udp_packet_axis_data <= 16'b0; // default to 0
            fifo_out_data_prev <= 16'b0; // default to 0
            udp_packet_axis_valid <= 1'b0;
        end else begin
            // First transaction 
            if (start_udp_header && !in_udp_header) begin
                // Assign tdata
                udp_packet_axis_data <= udp_packet[packet_state];
            end else if(in_udp_header) begin
            // If read enable is active, assign AXIS buffer to FIFO output
                udp_packet_axis_valid <= 1'b1;
                udp_packet_axis_data <= udp_packet[packet_state];
            end else if(fifo_0_read_en) begin
                udp_packet_axis_valid <= 1'b1;
                fifo_out_data_prev <= fifo_0_out_data;
                udp_packet_axis_data <= {fifo_0_out_data[47:0], fifo_out_data_prev[63:48]};
            end else if(fifo_1_read_en) begin
                udp_packet_axis_valid <= 1'b1;
                fifo_out_data_prev <= fifo_1_out_data;
                udp_packet_axis_data <= {fifo_1_out_data[47:0], fifo_out_data_prev[63:48]};
            end else begin
                udp_packet_axis_valid <= 1'b0;
            end
        end
    end

    wire capture_enable_m00;
    signal_clock_sync capture_enable_sync (
        .clk1_in(m00_axis_aclk),
        .signal_clk0(capture_enable_s01),
        .signal_clk1(capture_enable_m00)
    );

    // AXI4-Stream control signals
    assign m00_axis_tvalid = udp_packet_axis_valid && capture_enable_m00;     // Valid when we're in the middle of sending the packet
    assign m00_axis_tdata = m00_axis_tvalid ? udp_packet_axis_data : 64'h0;               // Transmit each 64-bit word of the UDP packet
    assign m00_axis_tuser = 1'b0;
    assign m00_axis_tlast = (packet_state == FINAL_STATE + 1) && m00_axis_tvalid; // Mark the last word of the packet
    assign m00_axis_tkeep = m00_axis_tlast ? 8'h3 : 8'hFF;

    assign s01_axis_tready = 1'b1;

    //////////////////////////////////////////////////////////////////////////
    // AXI4-Lite Control Bus
    //////////////////////////////////////////////////////////////////////////

    assign s00_axi_awready = 1'b1;
    assign s00_axi_wready = 1'b1;
    assign s00_axi_bresp = 2'b00;
    assign s00_axi_bvalid = s00_axi_wvalid;
    assign s00_axi_arready = 1'b1;
    assign s00_axi_rresp = 2'b00;

    wire pps_detect_s00;
    signal_clock_sync pps_detect_sync (
        .clk1_in(m00_axis_aclk),
        .signal_clk0(pps_detect_s01),
        .signal_clk1(pps_detect_s00)
    );

    wire received_counter_m00;
    signal_clock_sync received_counter_sync (
        .clk1_in(m00_axis_aclk),
        .signal_clk0(received_counter_s01),
        .signal_clk1(received_counter_m00)
    );

    // Write Logic
    always @(posedge s00_axi_aclk) begin
        if (~s00_axi_aresetn) begin
            eth_dst_mac[0] = 8'hFF;
            eth_dst_mac[1] = 8'hFF;
            eth_dst_mac[2] = 8'hFF;
            eth_dst_mac[3] = 8'hFF;
            eth_dst_mac[4] = 8'hFF;
            eth_dst_mac[5] = 8'hFF; // Broadcast MAC address
            eth_dst_mac_lsb[0] = 8'h00;
            eth_dst_mac_lsb[1] = 8'h00;
            eth_dst_mac_lsb[2] = 8'h00;
            eth_dst_mac_lsb[3] = 8'h00;
            sample_rate_numerator[63:0] = 64'd1228800000; // Default 1.2288Gsps
            sample_rate_denominator[63:0] = 64'd16; // Default 16x divisor
            frequency_idx[31:0] = 32'd0;
        end else if (s00_axi_awvalid && s00_axi_wvalid) begin
            // Handle AXI write logic
            case (s00_axi_awaddr)
                32'h0000_0000: begin 
                    user_reset_s00 <= s00_axi_wdata[0];
                    enable_next_pps_s00 <= s00_axi_wdata[1];
                end
                32'h0000_0004: frequency_idx[31:0] <= s00_axi_wdata[31:0];
                32'h0000_000C: begin
                    // Dest MAC LSB
                    eth_dst_mac_lsb[3] <= s00_axi_wdata[7:0];
                    eth_dst_mac_lsb[2] <= s00_axi_wdata[15:8];
                    eth_dst_mac_lsb[1] <= s00_axi_wdata[23:16];
                    eth_dst_mac_lsb[0] <= s00_axi_wdata[31:24];
                end
                32'h0000_0010: begin 
                    // Dest MAC MSB - Update header
                    eth_dst_mac[1] <= s00_axi_wdata[7:0];
                    eth_dst_mac[0] <= s00_axi_wdata[15:8];

                    eth_dst_mac[2] <= eth_dst_mac_lsb[0];
                    eth_dst_mac[3] <= eth_dst_mac_lsb[1];
                    eth_dst_mac[4] <= eth_dst_mac_lsb[2];
                    eth_dst_mac[5] <= eth_dst_mac_lsb[3];
                end
                32'h0000_0014: begin 
                    // Source IP
                    ip_header[15][7:0] <= s00_axi_wdata[7:0];
                    ip_header[14][7:0] <= s00_axi_wdata[15:8];
                    ip_header[13][7:0] <= s00_axi_wdata[23:16]; 
                    ip_header[12][7:0] <= s00_axi_wdata[31:24]; 
                end
                32'h0000_0018: begin 
                    // Destination IP
                    ip_header[19][7:0] <= s00_axi_wdata[7:0];    
                    ip_header[18][7:0] <= s00_axi_wdata[15:8];
                    ip_header[17][7:0] <= s00_axi_wdata[23:16];
                    ip_header[16][7:0] <= s00_axi_wdata[31:24];  
                end
                32'h0000_001C: begin 
                    // Source Port
                    udp_header[1][7:0] <= s00_axi_wdata[7:0];
                    udp_header[0][7:0] <= s00_axi_wdata[15:8];
                end
                32'h0000_0020: begin 
                    // Destination Port
                    udp_header[3][7:0] <= s00_axi_wdata[7:0];
                    udp_header[2][7:0] <= s00_axi_wdata[15:8];
                end
                32'h0000_0024: begin 
                    sample_idx_offset[31:0] <= s00_axi_wdata[31:0];
                end
                32'h0000_0028: begin 
                    sample_idx_offset[63:32] <= s00_axi_wdata[31:0];
                end
                32'h0000_0030: begin 
                    sample_rate_numerator[31:0] <= s00_axi_wdata[31:0];
                end
                32'h0000_0034: begin 
                    sample_rate_numerator[63:32] <= s00_axi_wdata[31:0];
                end
                32'h0000_0038: begin 
                    sample_rate_denominator[31:0] <= s00_axi_wdata[31:0];
                end
                32'h0000_003C: begin 
                    sample_rate_denominator[63:32] <= s00_axi_wdata[31:0];
                end
                default: begin
                    // Do nothing
                end
            endcase
        end 

        // Set user reset after pps_detect is triggered
        if (pps_detect_s00 && enable_next_pps_s00) begin
            user_reset_s00 <= 1'b0;
            enable_next_pps_s00 = 1'b0;
        end
    end

    // AXI4 Read Data (output the register value as 32-bit)
    always @(posedge s00_axi_aclk) begin
        if (~s00_axi_aresetn) begin
            s00_axi_rdata <= 32'b0;
        end else if (s00_axi_arvalid && !s00_axi_rvalid) begin
            case (s00_axi_araddr)
                32'h0000_0000: s00_axi_rdata = {30'h0, enable_next_pps_s00, user_reset_s00}; 
                32'h0000_0004: s00_axi_rdata = frequency_idx;
                32'h0000_0008: s00_axi_rdata = received_counter_s01;           
                32'h0000_000C: begin
                    s00_axi_rdata = {eth_dst_mac[2], eth_dst_mac[3], eth_dst_mac[4], eth_dst_mac[5]};
                end
                32'h0000_0010: begin 
                    s00_axi_rdata = {8'b0, 8'b0, eth_dst_mac[0], eth_dst_mac[1]};
                end
                32'h0000_0014: begin 
                    // Source IP
                    s00_axi_rdata = {ip_header[12], ip_header[13], ip_header[14], ip_header[15]};
                end
                32'h0000_0018: begin 
                    // Destination IP
                    s00_axi_rdata = {ip_header[16], ip_header[17], ip_header[18], ip_header[19]};
                end
                32'h0000_001C: begin 
                    // Source Port
                    s00_axi_rdata = {8'b0, 8'b0, udp_header[0], udp_header[1]};
                end
                32'h0000_0020: begin 
                    // Destination Port
                    s00_axi_rdata = {8'b0, 8'b0, udp_header[2], udp_header[3]};
                end
                32'h0000_0024: s00_axi_rdata = sample_idx_offset[31:0];
                32'h0000_0028: s00_axi_rdata = sample_idx_offset[63:32];
                32'h0000_002C: s00_axi_rdata = pps_count[31:0];
                32'h0000_0030: s00_axi_rdata = sample_rate_numerator[31:0];
                32'h0000_0034: s00_axi_rdata = sample_rate_numerator[63:32];
                32'h0000_0038: s00_axi_rdata = sample_rate_denominator[31:0];
                32'h0000_003C: s00_axi_rdata = sample_rate_denominator[63:32];
                default: s00_axi_rdata = 32'b0;
            endcase
        end
    end

    // AXI4 Read Data Valid
    reg rvalid_reg;
    always @(posedge s00_axi_aclk) begin
        if (~s00_axi_aresetn) begin
            rvalid_reg <= 1'b0;
        end else begin
            rvalid_reg <= s00_axi_arvalid && !rvalid_reg && s00_axi_rready;
        end
    end

    assign s00_axi_rvalid = rvalid_reg;

endmodule
