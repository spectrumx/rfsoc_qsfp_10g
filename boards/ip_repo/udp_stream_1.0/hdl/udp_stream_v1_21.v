`timescale 1 ns / 1 ps

module udp_stream_v1_0 #
(
    // Parameters of Axi Slave Bus Interface S00_AXI
    parameter integer C_S00_AXI_DATA_WIDTH	= 32,
    parameter integer C_S00_AXI_ADDR_WIDTH	= 6,

    // Parameters of Axi Master Bus Interface M00_AXIS
    parameter integer C_M00_AXIS_TDATA_WIDTH = 64,
    parameter integer C_M00_AXIS_TKEEP_WIDTH = 8,

    parameter integer FINAL_STATE = 21
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

    // Ports of Axi Master Bus Interface M00_AXIS
    input wire m00_axis_aclk,
    input wire m00_axis_aresetn,
    output wire m00_axis_tvalid,
    output wire [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata,
    output wire [C_M00_AXIS_TKEEP_WIDTH-1 : 0] m00_axis_tkeep,
    output wire m00_axis_tuser,
    output wire m00_axis_tlast,
    input wire m00_axis_tready

);

    // Define the UDP packet 
    reg [7:0] udp_packet_int[0:41];  // Ethernet frame, IP header, UDP header
    reg [63:0] udp_packet[0:21];     // 22 words for 64-bit chunks

    // Ethernet Header
    reg [7:0] eth_dst_mac[5:0];      // Destination MAC address (6 bytes)
    reg [7:0] eth_src_mac[5:0];      // Source MAC address (6 bytes)
    reg [7:0] eth_type[1:0];         // EtherType (e.g., 0x0800 for IPv4)

    // Initial IP Header Parts 
    reg [7:0] ip_header[0:19];       // Array to store 8-bit words of IP header
    reg [7:0] udp_header[0:7];       // Array to store 8-bit words of UDP header
    reg [31:0] sum;                  // IP Checksum
    reg [15:0] word;                 // 16-bit word for summing
    reg update_packet;
    reg [7:0] eth_dst_mac_lsb[3:0]; // Temp storage for Destination MAC LSB

    // Payload
    reg [15:0] payload[63:0];        // 64 short ints = 128 bytes

    // State machine signals
    reg [4:0] state;                 // Current state (0 to 5 to traverse the packet)
    reg [4:0] packet_index;          // Index for each 64-bit word in the UDP packet

    // AXI bus signals
    reg [7:0] tkeep_status;          // Signal to indicate valid bytes

    // Timer to trigger packet transmission every 100ms
    reg [31:0] counter;              // 32-bit counter for intervals
    reg [31:0] sent_counter;         // 32-bit counter for sent packets
    reg [31:0] packet_delay;        // Counter value to send packet
    reg trigger_send;                // Signal to trigger sending the packet

    // Initialize Ethernet frame, IP header, UDP header
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
        ip_header[2][7:0] = 8'h00;   // Total Length 20 + 8 + Payload
        ip_header[3][7:0] = 8'h9C;   // 156 (9C)
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
        udp_header[4][7:0] = 8'h00;   // Length 8 + Payload
        udp_header[5][7:0] = 8'h88;   // 136 (88)
        udp_header[6][7:0] = 8'h00;   // Checksum placeholder 
        udp_header[7][7:0] = 8'h00;   // 
    end

    // Assign payload
    integer i;
    integer incr;
    initial begin
        payload[0] = 0;
        payload[1] = 255;
        incr = 1;

        for (i = 2; i < 64; i = i + 2) begin
            payload[i] = incr; 
            payload[i+1] = 255 - incr;
            incr = incr + 1;
        end
    end

    initial begin
        update_packet = 1'b0;
        packet_delay = 32'd10000000;
    end

    // Calculate IP Checksum
    always @(posedge m00_axis_aclk or negedge m00_axis_aresetn) begin
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
    always @(posedge m00_axis_aclk or negedge m00_axis_aresetn) begin
        // Reassign static packet on reset or update
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

            // Payload

            // 64-bit udp packet
            udp_packet[0][63:0] <= {udp_packet_int[7], udp_packet_int[6], udp_packet_int[5], udp_packet_int[4], udp_packet_int[3], udp_packet_int[2], udp_packet_int[1], udp_packet_int[0]};
            udp_packet[1][63:0] <= {udp_packet_int[15], udp_packet_int[14], udp_packet_int[13], udp_packet_int[12], udp_packet_int[11], udp_packet_int[10], udp_packet_int[9], udp_packet_int[8]};
            udp_packet[2][63:0] <= {udp_packet_int[23], udp_packet_int[22], udp_packet_int[21], udp_packet_int[20], udp_packet_int[19], udp_packet_int[18], udp_packet_int[17], udp_packet_int[16]};
            udp_packet[3][63:0] <= {udp_packet_int[31], udp_packet_int[30], udp_packet_int[29], udp_packet_int[28], udp_packet_int[27], udp_packet_int[26], udp_packet_int[25], udp_packet_int[24]};
            udp_packet[4][63:0] <= {udp_packet_int[39], udp_packet_int[38], udp_packet_int[37], udp_packet_int[36], udp_packet_int[35], udp_packet_int[34], udp_packet_int[33], udp_packet_int[32]};
            udp_packet[5][63:0] <= {payload[2], payload[1], payload[0], udp_packet_int[41], udp_packet_int[40]};
            udp_packet[6][63:0] <= {payload[6], payload[5], payload[4], payload[3]};
            udp_packet[7][63:0] <= {payload[10], payload[9], payload[8], payload[7]};
            udp_packet[8][63:0] <= {payload[14], payload[13], payload[12], payload[11]};
            udp_packet[9][63:0] <= {payload[18], payload[17], payload[16], payload[15]};
            udp_packet[10][63:0] <= {payload[22], payload[21], payload[20], payload[19]};
            udp_packet[11][63:0] <= {payload[26], payload[25], payload[24], payload[23]};
            udp_packet[12][63:0] <= {payload[30], payload[29], payload[28], payload[27]};
            udp_packet[13][63:0] <= {payload[34], payload[33], payload[32], payload[31]};
            udp_packet[14][63:0] <= {payload[38], payload[37], payload[36], payload[35]};
            udp_packet[15][63:0] <= {payload[42], payload[41], payload[40], payload[39]};
            udp_packet[16][63:0] <= {payload[46], payload[45], payload[44], payload[43]};
            udp_packet[17][63:0] <= {payload[50], payload[49], payload[48], payload[47]};
            udp_packet[18][63:0] <= {payload[54], payload[53], payload[52], payload[51]};
            udp_packet[19][63:0] <= {payload[58], payload[57], payload[56], payload[55]};
            udp_packet[20][63:0] <= {payload[62], payload[61], payload[60], payload[59]};
            udp_packet[21][63:0] <= {48'd0, payload[63]};
        end
    end

    // Send UDP Packet over AXI bus
    always @(posedge m00_axis_aclk or negedge m00_axis_aresetn) begin
        if (~m00_axis_aresetn) begin
            counter <= 32'd0;
            sent_counter <= 32'd0;
            trigger_send <= 1'b0;
            state <= 5'd0;
            packet_index <= 5'd0;
            tkeep_status <= 8'h00;
        end else begin
            // Timer logic
            if ((counter == packet_delay) && (packet_delay != 0)) begin  // Adjust to 100 MHz clock
                trigger_send <= 1'b1;
                counter <= 32'd0;
            end else begin
                counter <= counter + 1;
                trigger_send <= 1'b0;
            end

            // State machine to send the UDP packet over AXI4 Stream
            if (trigger_send) begin
                // Reset state to start a new packet transmission
                state <= 5'd0;
                packet_index <= 5'd0;
                trigger_send <= 1'b0; // Clear the trigger after starting
                tkeep_status <= 8'hFF;
            end else if (m00_axis_tvalid && m00_axis_tready) begin
                // State machine to stream the UDP packet in 64-bit chunks
                if (state == 5'd0) begin
                    sent_counter <= sent_counter + 1;
                end
                if (state < FINAL_STATE) begin
                    packet_index <= packet_index + 1;
                end
                if( state == (FINAL_STATE-1)) begin
                    tkeep_status <= 8'h03;
                end
                if( state == FINAL_STATE) begin
                    tkeep_status <= 8'h00;
                end
                if (state <= FINAL_STATE) begin
                    state <= state + 1;
                end
                if( state == (FINAL_STATE+1)) begin
                    tkeep_status <= 8'h00;
                end
            end
        end
    end

    // AXI4-Stream signals
    // assign m00_axis_tvalid = (state <= 3'd5);   // Valid when we're in the middle of sending the packet
    assign m00_axis_tkeep = tkeep_status;
    assign m00_axis_tvalid = (state <= FINAL_STATE);   // Valid when we're in the middle of sending the packet
    assign m00_axis_tdata = udp_packet[packet_index];           // Transmit each 64-bit word of the UDP packet
    assign m00_axis_tuser = 1'b0;
    // assign m00_axis_tlast = (state == 3'd5) && m00_axis_tvalid; // Mark the last word of the packet
    assign m00_axis_tlast = (state == FINAL_STATE) && m00_axis_tvalid; // Mark the last word of the packet

    // AXI4-Lite signals
    assign s00_axi_awready = 1'b1;
    assign s00_axi_wready = 1'b1;
    assign s00_axi_bresp = 2'b00;
    assign s00_axi_bvalid = s00_axi_wvalid;
    assign s00_axi_arready = 1'b1;
    assign s00_axi_rresp = 2'b00;
    //assign s00_axi_rvalid = s00_axi_arvalid;

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
                32'h0000_0008: packet_delay[31:0] <= s00_axi_wdata[31:0];
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
                    update_packet = 1'b1;
                end
                32'h0000_0014: begin 
                    // Source IP
                    ip_header[15][7:0] <= s00_axi_wdata[7:0];
                    ip_header[14][7:0] <= s00_axi_wdata[15:8];
                    ip_header[13][7:0] <= s00_axi_wdata[23:16]; 
                    ip_header[12][7:0] <= s00_axi_wdata[31:24]; 
                    update_packet = 1'b1;
                end
                32'h0000_0018: begin 
                    // Destination IP
                    ip_header[19][7:0] <= s00_axi_wdata[7:0];    
                    ip_header[18][7:0] <= s00_axi_wdata[15:8];
                    ip_header[17][7:0] <= s00_axi_wdata[23:16];
                    ip_header[16][7:0] <= s00_axi_wdata[31:24];  
                    update_packet = 1'b1;
                end
                32'h0000_001C: begin 
                    // Source Port
                    udp_header[1][7:0] <= s00_axi_wdata[7:0];
                    udp_header[0][7:0] <= s00_axi_wdata[15:8];
                    update_packet = 1'b1;
                end
                32'h0000_0020: begin 
                    // Destination Port
                    udp_header[3][7:0] <= s00_axi_wdata[7:0];
                    udp_header[2][7:0] <= s00_axi_wdata[15:8];
                    update_packet = 1'b1;
                end
                default: begin
                    // Do nothing
                end
            endcase
        end
    end

    // AXI4 Read Data (output the register value as 32-bit)
    always @(posedge s00_axi_aclk or negedge s00_axi_aresetn) begin
        if (~s00_axi_aresetn) begin
            s00_axi_rdata <= 32'b0;
        end else if (s00_axi_arvalid && !s00_axi_rvalid) begin
            case (s00_axi_araddr)
                32'h0000_0000: s00_axi_rdata = sent_counter; 
                32'h0000_0004: s00_axi_rdata = counter;       
                32'h0000_0008: s00_axi_rdata = packet_delay;           
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
                default: s00_axi_rdata = 32'b0;
            endcase
        end
    end

    // AXI4 Read Data Valid
    reg rvalid_reg;
    always @(posedge s00_axi_aclk or negedge s00_axi_aresetn) begin
        if (~s00_axi_aresetn) begin
            rvalid_reg <= 1'b0;
        end else begin
            rvalid_reg <= s00_axi_arvalid && !rvalid_reg && s00_axi_rready;
        end
    end

    assign s00_axi_rvalid = rvalid_reg;

endmodule
