`timescale 1 ns / 1 ps

module udp_stream_v1_0 #
(
    // Parameters of Axi Slave Bus Interface S00_AXI
    parameter integer C_S00_AXI_DATA_WIDTH	= 32,
    parameter integer C_S00_AXI_ADDR_WIDTH	= 5,

    // Parameters of Axi Master Bus Interface M00_AXIS
    parameter integer C_M00_AXIS_TDATA_WIDTH = 64
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
    output wire m00_axis_tlast,
    input wire m00_axis_tready

);

    // Define the UDP packet (fixed example from the previous response)
    reg [63:0] udp_packet[0:3];  // 4 words (512-bit packet) for 64-bit chunks
    
    // Initial IP Header Parts (Before checksum)
    reg [7:0] ip_header[0:19];   // Array to store 8-bit words of IP header
    reg [31:0] sum; // IP Checksum
    reg [7:0] udp_header[0:7];   // Array to store 8-bit words of UDP header

    // State machine signals
    reg [1:0] state;          // Current state (0 to 3 to traverse the packet)
    reg [1:0] packet_index;   // Index for each 64-bit word in the UDP packet

    // Timer to trigger packet transmission every second
    reg [31:0] counter;       // 32-bit counter for 1-second intervals
    reg [31:0] sent_counter;  // 32-bit counter for sent packets
    reg trigger_send;         // Signal to trigger sending the packet


    // IP header (40 bytes, now 8-bit wide)
    initial begin
        ip_header[0][7:0] = 8'h45;   // Version (4) + Header Length (5)
        ip_header[1][7:0] = 8'h00;
        ip_header[2][7:0] = 8'h00;   // Total Length (32 bytes)
        ip_header[3][7:0] = 8'h20;
        ip_header[4][7:0] = 8'h00;   // Identification (0)
        ip_header[5][7:0] = 8'h00;
        ip_header[6][7:0] = 8'h40;   // Flags and Fragment Offset
        ip_header[7][7:0] = 8'h00;
        ip_header[8][7:0] = 8'h40;   // TTL (64) and protocol (UDP)
        ip_header[9][7:0] = 8'h11;
        ip_header[10][7:0] = 8'h00;   // Checksum placeholder B117
        ip_header[11][7:0] = 8'h00;
        ip_header[12][7:0] = 8'hC0;   // Source IP (192.168.4.99)
        ip_header[13][7:0] = 8'hA8;
        ip_header[14][7:0] = 8'h04;
        ip_header[15][7:0] = 8'h63;
        ip_header[16][7:0] = 8'hC0;   // Destination IP (192.168.4.1) 
        ip_header[17][7:0] = 8'hA8;
        ip_header[18][7:0] = 8'h04;
        ip_header[19][7:0] = 8'h01;  
    end

    integer i;
    initial begin
        sum = 32'b0;

        for (i = 0; i < 20; i = i + 1) begin
            sum = sum + ip_header[i];
        end
        sum = sum + (sum >> 16);  // Add overflow from the upper 16 bits
        ip_header[10] = ~sum[7:0];  // One's complement 
        ip_header[11] = ~sum[15:8];
    end

    // UDP header (16 bytes, now 8-bit wide)
    initial begin
        udp_header[0][7:0] = 8'h30;   // Source port
        udp_header[1][7:0] = 8'h39;
        udp_header[2][7:0] = 8'h30;   // Dest port
        udp_header[3][7:0] = 8'h3A;
        udp_header[4][7:0] = 8'h00;   // Length
        udp_header[5][7:0] = 8'h0C;
        udp_header[6][7:0] = 8'h00;   // Checksum (Optional)
        udp_header[7][7:0] = 8'h00;
    end

    always @(posedge m00_axis_aclk or negedge m00_axis_aresetn) begin
        if (~m00_axis_aresetn) begin
            // udp_packet[0] = {ip_header[0], ip_header[1], ip_header[2], ip_header[3], ip_header[4], ip_header[5], ip_header[6], ip_header[7]};
            // udp_packet[1] = {ip_header[8], ip_header[9], ip_header[10], ip_header[11], ip_header[12], ip_header[13], ip_header[14], ip_header[15]};
            // udp_packet[2] = {ip_header[16], ip_header[17], ip_header[18], ip_header[19], udp_header[0], udp_header[1], udp_header[2], udp_header[3]};
            // udp_packet[3] = {udp_header[4], udp_header[5], udp_header[6], udp_header[7], 32'hDEADBEEF};  
            udp_packet[0] = {ip_header[7], ip_header[6], ip_header[5], ip_header[4], ip_header[3], ip_header[2], ip_header[1], ip_header[0]};
            udp_packet[1] = {ip_header[15], ip_header[14], ip_header[13], ip_header[12], ip_header[11], ip_header[10], ip_header[9], ip_header[8]};
            udp_packet[2] = {udp_header[3], udp_header[2], udp_header[1], udp_header[0], ip_header[19], ip_header[18], ip_header[17], ip_header[16]};
            udp_packet[3] = {32'hDEADBEEF, udp_header[7], udp_header[6], udp_header[5], udp_header[4]};
        end
    end

    always @(posedge m00_axis_aclk or negedge m00_axis_aresetn) begin
        if (~m00_axis_aresetn) begin
            counter <= 32'd0;
            sent_counter <= 32'd0;
            trigger_send <= 1'b0;
            state <= 2'd0;
            packet_index <= 2'd0;
        end else begin
            // Timer logic (simulate 1-second interval with a clock cycle counter)
            //if (counter == 32'd100000000) begin  // Adjust to 100 MHz clock
            if (counter == 32'd100000) begin  // Adjust to 100 MHz clock
                trigger_send <= 1'b1;
                counter <= 32'd0;
                sent_counter <= sent_counter + 1;
            end else begin
                counter <= counter + 1;
                trigger_send <= 1'b0;
            end

            // State machine to send the UDP packet over AXI4 Stream
            if (trigger_send) begin
                // Reset state to start a new packet transmission
                state <= 2'd0;
                packet_index <= 2'd0;
                trigger_send <= 1'b0; // Clear the trigger after starting
            end else if (m00_axis_tvalid && m00_axis_tready) begin
                // State machine to stream the UDP packet in 64-bit chunks
                if (state < 2'd3) begin
                    state <= state + 1;
                    packet_index <= packet_index + 1;
                end
            end
        end
    end

    // AXI4-Stream signals
    assign m00_axis_tvalid = (state < 2'd3);   // Valid when we're in the middle of sending the packet
    assign m00_axis_tdata = udp_packet[packet_index];           // Transmit each 64-bit word of the UDP packet
    assign m00_axis_tlast = (state == 2'd3) && m00_axis_tvalid; // Mark the last word of the packet

    // AXI4-Lite signals
    assign s00_axi_awready = 1'b1;
    assign s00_axi_wready = 1'b1;
    assign s00_axi_bresp = 2'b00;
    assign s00_axi_bvalid = s00_axi_wvalid;
    assign s00_axi_arready = 1'b1;
    assign s00_axi_rresp = 2'b00;
    //assign s00_axi_rvalid = s00_axi_arvalid;

    // AXI4 Read Data (output the register value as 32-bit)
    always @(posedge s00_axi_aclk or negedge s00_axi_aresetn) begin
        if (~s00_axi_aresetn) begin
            s00_axi_rdata <= 32'b0;
        end else if (s00_axi_arvalid && !s00_axi_rvalid) begin
            case (s00_axi_araddr)
                32'h0000_0000: s00_axi_rdata = sent_counter; 
                32'h0000_0001: s00_axi_rdata = counter;       
                32'h0000_0002: s00_axi_rdata = sum;           
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
