///////////////////////////////////////////////////////////////////////////////
// adc_to_udp_stream_v1_0.v
//
// Convert 64-bit I/Q stream from ADC block to UDP Packets 
// on a 64-bit AXIS Bus
//
//  Assumes constant stream from 64-bit input
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

module adc_to_udp_stream_v1_0 #
(
    // Parameters of Axi Slave Bus Interface S00_AXI
    parameter integer C_S00_AXI_DATA_WIDTH	= 32,
    parameter integer C_S00_AXI_ADDR_WIDTH	= 6,

    // Parameters of Input AXIS Slave Bus Interface S01_AXIS
    parameter integer C_S01_AXIS_TDATA_WIDTH = 64, 

    // Parameters of Output AXIS Master Bus Interface M00_AXIS
    parameter integer C_M00_AXIS_TDATA_WIDTH = 64,
    parameter integer C_M00_AXIS_TKEEP_WIDTH = 8
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
    input wire m00_axis_tready
);

    // Local params
    // localparam integer PAYLOAD_WORDS = 4128;                            // Payload length (in 16-bit words)
    // localparam integer PAYLOAD_WORDS = 4096;                            // Payload length (in 16-bit words)
    localparam integer PAYLOAD_WORDS = 4100;                            // Payload length (in 16-bit words)
    localparam integer FIFO_LENGTH = 2048; //2048; //PAYLOAD_WORDS / 4 + FIFO_BUFFER ;            // Payload length (in 16-bit words) + buffer
    localparam integer FIFO_BUFFER = FIFO_LENGTH - (PAYLOAD_WORDS/4);
    localparam integer UDP_HEADER_LENGTH = 8 + (PAYLOAD_WORDS * 2); // 8 bytes (UDP header) + 2 bytes/word * payload_length
    localparam integer IP_HEADER_LENGTH  = 20 + UDP_HEADER_LENGTH;      // 20 bytes (IP header) + UDP length
    localparam integer TOTAL_HEADER_LENGTH = 14 + IP_HEADER_LENGTH;     // 14 bytes (Ethernet header) + IP length

    localparam integer HEADER_STATE = 6;                                  // States to tx (words + headers)
    localparam integer FINAL_STATE = (PAYLOAD_WORDS / 4) + HEADER_STATE;  // States to tx (words + headers)

    localparam integer WORDS_PER_AXIS = C_S01_AXIS_TDATA_WIDTH / 16;          // 16-bit words
    localparam integer AXIS_PER_BUFFER = PAYLOAD_WORDS / WORDS_PER_AXIS;     // Ping-pong buffer size

    localparam integer FIFO_READ_DELAY = 2;

    // Ping-pong buffer 
    wire buffer_select;

    wire fifo_0_write_en;
    wire fifo_1_write_en;
    wire fifo_0_read_en;
    wire fifo_1_read_en;
    wire [C_M00_AXIS_TDATA_WIDTH-1:0] fifo_0_out_data;
    wire [C_M00_AXIS_TDATA_WIDTH-1:0] fifo_1_out_data;

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
    wire update_packet;

    // State machine signals
    reg [15:0] packet_state;                    // Current state/index (0 to 5 to traverse the packet header)

    // AXI bus signals
    reg [C_M00_AXIS_TDATA_WIDTH-1:0] udp_packet_axis_data;           
    reg [C_M00_AXIS_TDATA_WIDTH-1:0] fifo_out_data_prev;           

    // Timer to trigger packet transmission every 100ms
    reg [63:0] sent_counter;                    // 64-bit counter for sent packets
    reg [31:0] received_counter;                // 32-bit counter for received AXIS transactions
    reg [31:0] full_buffer_counter;             // 32-bit counter for full buffers
    reg [7:0] user_reset;                       // State of user reset

    // FIFO
    wire fifo_0_full;
    wire fifo_1_full;
    wire fifo_0_empty;
    wire fifo_1_empty;
    reg fifo_0_reset;
    reg fifo_1_reset;
    wire fifo_0_rst_busy;
    wire fifo_1_rst_busy;

    reg fifo_0_full_reg;
    reg fifo_1_full_reg;
    reg fifo_0_full_delay;
    reg fifo_1_full_delay;
    wire fifo_0_full_trigger;
    wire fifo_1_full_trigger;
    reg fifo_0_read_en_latched;
    reg fifo_1_read_en_latched;

    reg fifo_0_rst_busy_latched;
    reg fifo_1_rst_busy_latched;

    wire fifo_0_rst_busy_combined;
    wire fifo_1_rst_busy_combined;

    reg fifo_0_empty_latched;
    reg fifo_1_empty_latched;

    //////////////////////////////////////////////////////////////////////////
    // Ping-pong buffer for incoming ADC samples
    // Use block ram FIFO
    //////////////////////////////////////////////////////////////////////////
    always @(posedge s01_axis_aclk or negedge s01_axis_aresetn) begin
        if (!s01_axis_aresetn) begin
            received_counter <= 0;
            fifo_0_rst_busy_latched <= 0;
            fifo_1_rst_busy_latched <= 0;
            fifo_0_reset <= 1;
            fifo_1_reset <= 1;
        end else begin
            // Write data to the appropriate buffer
            // Increment counter
            if (s01_axis_tvalid) begin
                received_counter <= received_counter + 1;
            end

            // Latch reset busy to delay extra cycle
            fifo_0_rst_busy_latched <= fifo_0_rst_busy;
            fifo_1_rst_busy_latched <= fifo_1_rst_busy;

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
    assign fifo_0_rst_combined = fifo_0_rst_busy || fifo_0_rst_busy_latched;
    assign fifo_1_rst_combined = fifo_1_rst_busy || fifo_1_rst_busy_latched;
    assign fifo_0_rst_busy = fifo_0_wr_rst_busy || fifo_0_rd_rst_busy;
    assign fifo_1_rst_busy = fifo_1_wr_rst_busy || fifo_1_rd_rst_busy;
    assign buffer_select = fifo_0_full | fifo_0_full_reg;
    assign fifo_0_write_en = s01_axis_tvalid && s01_axis_aresetn && !fifo_0_rst_combined && !buffer_select;
    assign fifo_1_write_en = s01_axis_tvalid && s01_axis_aresetn && !fifo_1_rst_combined && buffer_select;

    // Flag fifo full transition for a single cycle
    always @(posedge m00_axis_aclk) begin
        if (!m00_axis_aresetn) begin
            fifo_0_full_reg <= 1'b0;
            fifo_0_full_delay <= 1'b0;
            fifo_1_full_reg <= 1'b0;
            fifo_1_full_delay <= 1'b0;
            full_buffer_counter <= 1'b0;
        end else begin
            if(fifo_0_full) begin
                fifo_0_full_reg <= 1'b1;
                full_buffer_counter <= full_buffer_counter + 1;
                if (!fifo_1_full) begin
                    fifo_1_full_reg <= 1'b0;
                end
            end
            if(fifo_1_full) begin
                fifo_1_full_reg <= 1'b1;
                full_buffer_counter <= full_buffer_counter + 1;
                if (!fifo_0_full) begin
                    fifo_0_full_reg <= 1'b0;
                end
            end

            fifo_0_full_delay <= fifo_0_full_reg;
            fifo_1_full_delay <= fifo_1_full_reg;
        end
    end

    assign fifo_0_full_trigger = fifo_0_full_reg && !fifo_0_full_delay;
    assign fifo_1_full_trigger = fifo_1_full_reg && !fifo_1_full_delay;
    assign update_packet = fifo_0_full_trigger || fifo_1_full_trigger;

    wire [11:0] fifo_0_wr_count;
    wire [11:0] fifo_1_wr_count;
    wire [11:0] fifo_0_rd_count;
    wire [11:0] fifo_1_rd_count;
    wire fifo_0_wr_rst_busy;
    wire fifo_0_rd_rst_busy;
    wire fifo_1_wr_rst_busy;
    wire fifo_1_rd_rst_busy;

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

        // Write side
        .wr_clk(s01_axis_aclk),
        .wr_en(fifo_0_write_en),
        .din(s01_axis_tdata),
        // .full(fifo_0_full),
        .prog_full(fifo_0_full),
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

        // Write side
        .wr_clk(s01_axis_aclk),
        .wr_en(fifo_1_write_en),
        .din(s01_axis_tdata),
        // .full(fifo_1_full),
        .prog_full(fifo_1_full),
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
        udp_header[0][7:0] = 8'hEA;   // Source port 60133
        udp_header[1][7:0] = 8'hE5;
        udp_header[2][7:0] = 8'hEA;   // Dest port 60133
        udp_header[3][7:0] = 8'hE5;
        udp_header[4][7:0] = UDP_HEADER_LENGTH[15:8];  // UDP Length MSB
        udp_header[5][7:0] = UDP_HEADER_LENGTH[7:0];   // UDP Length LSB
        udp_header[6][7:0] = 8'h00;   // Checksum placeholder 
        udp_header[7][7:0] = 8'h00;   // 

        // UDP Packet - initialize to 0
        for (i = 0; i < 42; i = i + 1) begin
            udp_packet_int[i] = 8'b0;
        end
        for (i = 0; i <= FINAL_STATE; i = i + 1) begin
            udp_packet[i] = 64'b0;
        end
    end

    // Initialize state
    initial begin
        user_reset = 8'b0;
    end

    // Calculate IP Checksum
    always @(posedge m00_axis_aclk) begin
        // Reassign static packet on reset
        if ((m00_axis_aresetn == 1'b0) || (update_packet == 1'b1)) begin
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
        if ((m00_axis_aresetn == 1'b0) || (update_packet == 1'b1)) begin
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

            // Assign payload from input stream buffer
            // Align ADC data with next full AXIS transacation
            // Sequence # + size
            udp_packet[5][63:0] <= {udp_packet_axis_data[63:16], udp_packet_int[41], udp_packet_int[40]};
        end
    end

    //////////////////////////////////////////////////////////////////////////
    // AXI4 Stream Data Bus
    //////////////////////////////////////////////////////////////////////////
    // Send UDP Packet over AXI bus
    assign start_payload = (packet_state >= (HEADER_STATE-FIFO_READ_DELAY)) && (packet_state <= FINAL_STATE);
    assign in_payload = (packet_state >= HEADER_STATE) && (packet_state <= FINAL_STATE);

    wire in_payload;
    reg udp_packet_axis_valid;
    always @(posedge m00_axis_aclk) begin
        if (~m00_axis_aresetn) begin
            sent_counter <= 64'd0;
            packet_state <= 16'd0;
            fifo_0_read_en_latched <= 0;
            fifo_1_read_en_latched <= 0;
            start_udp_header <= 0;
            in_udp_header <= 0;
        end else begin
            // State machine to send the UDP packet over AXI4 Stream
            // start when input stream buffer is full
            if (update_packet) begin
                // Reset state to start a new packet transmission
                packet_state <= 16'd0;
                start_udp_header <= 1'b1;
                sent_counter <= sent_counter + 1;       // Increment packets sent counter
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
                if (fifo_1_full_reg) begin
                    fifo_1_read_en_latched <= 1;
                end

                // Buffer select = 1, read from Buffer 0 
                if (fifo_0_full_reg) begin
                    fifo_0_read_en_latched <= 1;
                end
            end

            // Reset read enables when fifo is empty
            // of buffer is active for write
            if (fifo_0_empty || !buffer_select) begin
                fifo_0_read_en_latched <= 0;
            end

            if (fifo_1_empty || buffer_select) begin
                fifo_1_read_en_latched <= 0;
            end
        end

    end

    // Assign the latched values to the read enables
    // disable when tready is low
    assign fifo_0_read_en = fifo_0_read_en_latched && start_payload && m00_axis_tready && !fifo_0_rst_busy;
    assign fifo_1_read_en = fifo_1_read_en_latched && start_payload && m00_axis_tready && !fifo_1_rst_busy;

    always @(posedge m00_axis_aclk) begin
        if (~m00_axis_aresetn) begin
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

    // AXI4-Stream control signals
    assign m00_axis_tvalid = udp_packet_axis_valid;     // Valid when we're in the middle of sending the packet
    assign m00_axis_tdata = m00_axis_tvalid ? udp_packet_axis_data : 64'd0;               // Transmit each 64-bit word of the UDP packet
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

    // Write Logic: when AXI4 Write transaction occurs, write the data to char_reg
    always @(posedge s00_axi_aclk or negedge s00_axi_aresetn) begin
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
        end else if (s00_axi_awvalid && s00_axi_wvalid) begin
            case (s00_axi_awaddr)
                32'h0000_0000: user_reset[7:0] <= s00_axi_wdata[7:0];
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
                default: begin
                    // Do nothing
                end
            endcase
        end
    end

    // AXI4 Read Data (output the register value as 32-bit)
    always @(posedge s00_axi_aclk) begin
        if (~s00_axi_aresetn) begin
            s00_axi_rdata <= 32'b0;
        end else if (s00_axi_arvalid && !s00_axi_rvalid) begin
            case (s00_axi_araddr)
                32'h0000_0000: s00_axi_rdata = user_reset; 
                32'h0000_0004: s00_axi_rdata = sent_counter[31:0];       
                32'h0000_0008: s00_axi_rdata = received_counter;           
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
                32'h0000_0024: s00_axi_rdata = full_buffer_counter;
                32'h0000_0028: s00_axi_rdata = {16'b0, 5'b0, m00_axis_aresetn, m00_axis_tready, m00_axis_tvalid, 5'b0, s01_axis_aresetn, s01_axis_tready, s01_axis_tvalid};
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
