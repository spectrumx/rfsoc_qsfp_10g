///////////////////////////////////////////////////////////////////////////////
// adc_to_udp_stream_tb.v
//
//  Testbench for adc_to_udp_stream
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

module adc_to_udp_stream_v1_0_tb;

    // Control AXI bus
    parameter integer C_S00_AXI_DATA_WIDTH	= 32;
    parameter integer C_S00_AXI_ADDR_WIDTH	= 6;

    // Incoming AXIS bus
    parameter integer C_S01_AXIS_TDATA_WIDTH = 64;

    // Outgoing AXIS bus
    parameter integer C_M00_AXIS_TDATA_WIDTH = 64;
    parameter integer C_M00_AXIS_TKEEP_WIDTH = 8;

    // Default UDP Port
    parameter integer UDP_PORT = 60133;

    // Clock and Reset signals for AXI4-Lite (S00_AXI)
    reg s00_axi_aclk;
    reg s00_axi_aresetn;

    // Incoming AXI4-Stream Interface signals
    reg s01_axis_aclk;
    reg s01_axis_aresetn;

    // Outgoing AXI4-Stream Interface signals
    reg m00_axis_aclk;
    reg m00_axis_aresetn;

    // Signals for AXI4-Lite (S00_AXI)
    reg [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr;
    reg [2 : 0] s00_axi_awprot;
    reg s00_axi_awvalid;
    wire s00_axi_awready;
    reg [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata;
    reg [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb;
    reg s00_axi_wvalid;
    reg s00_axi_wready;
    reg [1 : 0] s00_axi_bresp;
    wire s00_axi_bvalid;
    reg s00_axi_bready;
    wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr;
    wire [2 : 0] s00_axi_arprot;
    wire s00_axi_arvalid;
    reg s00_axi_arready;
    reg [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata;
    reg [1 : 0] s00_axi_rresp;
    reg s00_axi_rvalid;
    wire s00_axi_rready;

    // Incoming AXIS signals
    reg s01_axis_tvalid;
    reg [C_S01_AXIS_TDATA_WIDTH-1 : 0] s01_axis_tdata;
    wire s01_axis_tready;

    // Outgoing AXIS signals
    wire m00_axis_tvalid;
    wire [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata;
    wire [C_M00_AXIS_TKEEP_WIDTH-1 : 0] m00_axis_tkeep;
    wire m00_axis_tlast;
    wire m00_axis_tuser;
    reg m00_axis_tready;

    // Instantiate the ADC to UDP Stream module
    adc_to_udp_stream_v1_0 #(
        .C_S00_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S00_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH),
        .C_S01_AXIS_TDATA_WIDTH(C_S01_AXIS_TDATA_WIDTH),
        .C_M00_AXIS_TDATA_WIDTH(C_M00_AXIS_TDATA_WIDTH),
        .C_M00_AXIS_TKEEP_WIDTH(C_M00_AXIS_TKEEP_WIDTH),
        .UDP_PORT(UDP_PORT)
    ) dut (
        .s00_axi_aclk(s00_axi_aclk),
        .s00_axi_aresetn(s00_axi_aresetn),
        .s00_axi_awaddr(s00_axi_awaddr),
        .s00_axi_awprot(s00_axi_awprot),
        .s00_axi_awvalid(s00_axi_awvalid),
        .s00_axi_awready(s00_axi_awready),
        .s00_axi_wdata(s00_axi_wdata),
        .s00_axi_wstrb(s00_axi_wstrb),
        .s00_axi_wvalid(s00_axi_wvalid),
        .s00_axi_wready(s00_axi_wready),
        .s00_axi_bresp(s00_axi_bresp),
        .s00_axi_bvalid(s00_axi_bvalid),
        .s00_axi_bready(s00_axi_bready),
        .s00_axi_araddr(s00_axi_araddr),
        .s00_axi_arprot(s00_axi_arprot),
        .s00_axi_arvalid(s00_axi_arvalid),
        .s00_axi_arready(s00_axi_arready),
        .s00_axi_rdata(s00_axi_rdata),
        .s00_axi_rresp(s00_axi_rresp),
        .s00_axi_rvalid(s00_axi_rvalid),
        .s00_axi_rready(s00_axi_rready),

        .s01_axis_aclk(s01_axis_aclk),
        .s01_axis_aresetn(s01_axis_aresetn),
        .s01_axis_tvalid(s01_axis_tvalid),
        .s01_axis_tdata(s01_axis_tdata),
        .s01_axis_tready(s01_axis_tready),

        .m00_axis_aclk(m00_axis_aclk),
        .m00_axis_aresetn(m00_axis_aresetn),
        .m00_axis_tvalid(m00_axis_tvalid),
        .m00_axis_tdata(m00_axis_tdata),
        .m00_axis_tkeep(m00_axis_tkeep),
        .m00_axis_tuser(m00_axis_tuser),
        .m00_axis_tlast(m00_axis_tlast),
        .m00_axis_tready(m00_axis_tready)
    );

    // Clock generation for AXI4-Lite (S00_AXI) (156.25MHz)
    initial begin
        s00_axi_aclk = 0;
        forever #3.2ns s00_axi_aclk = ~s00_axi_aclk;  // Toggle  every .32ns
    end

    // Clock generation for AXI4-Stream (S01_AXIS) (38.4MHz)
    initial begin
        s01_axis_aclk = 0;
        forever #13.02ns s01_axis_aclk = ~s01_axis_aclk;  // Toggle 
    end

    // Clock generation for AXI4-Stream (M00_AXIS) (156.25 MHz)
    initial begin
        m00_axis_aclk = 0;
        forever #3.2ns m00_axis_aclk = ~m00_axis_aclk;  // Toggle 
    end

    // Reset generation
    initial begin
        s00_axi_aresetn = 1;
        s01_axis_aresetn = 0;
        m00_axis_aresetn = 0;
        #20;                    // Deassert reset after 20 ns
        m00_axis_aresetn = 1;  
        s01_axis_aresetn = 1;
    end

    // Test logic
    integer i;
    longint input_stream_data;
    bit tvalid_high = 0;

    // Write to reg 0 to disable user reset 
    initial begin
        // Initialize S00 signals
        s00_axi_awaddr = 32'h0;
        s00_axi_awprot = 3'h0;
        s00_axi_wstrb = 4'h0;
        s00_axi_bready = 1'b0;

        s00_axi_wdata = 32'h00;
        s00_axi_awvalid = 1'b0;
        s00_axi_wvalid = 1'b0;

        // Write 8'h1 to address 0 on s00 AXI bus at 20us
        #55us; 
        s00_axi_awaddr = 32'h0; // Address 0
        s00_axi_awprot = 3'h0;  // Write address not protected
        s00_axi_awvalid = 1'b1; // Write address valid

        // Wait for AWREADY and clock edge
        @(posedge s00_axi_aclk);
        while (!s00_axi_awready) @(posedge s00_axi_aclk); // Wait until ready

        s00_axi_wdata = 32'h0;  // Set reset low
        s00_axi_wstrb = 4'hF;   // Write all 4 bytes
        s00_axi_wvalid = 1'b1;  // Write valid

        // Wait for WREADY
        @(posedge s00_axi_aclk);
        while (!s00_axi_awready) @(posedge s00_axi_aclk); // Wait until ready
        s00_axi_wvalid = 1'b0;
        s00_axi_awvalid = 1'b0;

        // Wait for BVALID and respond
        @(posedge s00_axi_aclk);
        while (!s00_axi_bvalid) @(posedge s00_axi_aclk);
        s00_axi_bready = 1'b1;
        @(posedge s00_axi_aclk);
        s00_axi_bready = 1'b0;
    end

    // Write to reg 1 to enable user reset 
    initial begin
        // Initialize S00 signals
        s00_axi_awaddr = 32'h0;
        s00_axi_awprot = 3'h0;
        s00_axi_wstrb = 4'h0;
        s00_axi_bready = 1'b0;

        s00_axi_wdata = 32'h00;
        s00_axi_awvalid = 1'b0;
        s00_axi_wvalid = 1'b0;

        // Write 8'h0 to address 0 on s00 AXI bus at 20us
        #190us; 
        s00_axi_awaddr = 32'h0; // Address 0
        s00_axi_awprot = 3'h0;  // Write address not protected
        s00_axi_awvalid = 1'b1; // Write address valid

        // Wait for AWREADY and clock edge
        @(posedge s00_axi_aclk);
        while (!s00_axi_awready) @(posedge s00_axi_aclk); // Wait until ready

        s00_axi_wdata = 32'h1;  // Set reset high
        s00_axi_wstrb = 4'hF;   // Write all 4 bytes
        s00_axi_wvalid = 1'b1;  // Write valid

        // Wait for WREADY
        @(posedge s00_axi_aclk);
        while (!s00_axi_awready) @(posedge s00_axi_aclk); // Wait until ready
        s00_axi_wvalid = 1'b0;
        s00_axi_awvalid = 1'b0;

        // Wait for BVALID and respond
        @(posedge s00_axi_aclk);
        while (!s00_axi_bvalid) @(posedge s00_axi_aclk);
        s00_axi_bready = 1'b1;
        @(posedge s00_axi_aclk);
        s00_axi_bready = 1'b0;
    end

    // Disable m00 tready to check that output data stream pauses
    initial begin
        // Initialize tready to high
        m00_axis_tready = 1'b1;

        // Disable and reenable tready
        #55us m00_axis_tready = 1'b0;
        #5us m00_axis_tready = 1'b1;
    end

    // Send incrementing data to input stream
    initial begin
        // Initialize incoming AXIS signals
        s01_axis_tvalid = 0;
        s01_axis_tdata = 0;

        input_stream_data = 64'h007CB66BA55A0000;

        // Wait for reset deassertion
        @(posedge m00_axis_aresetn);

        // Test the transmission of four UDP packets
        repeat (8256) begin
            // Incoming data
            @(posedge s01_axis_aclk);
            while (!s01_axis_tready) @(posedge s01_axis_aclk);
            s01_axis_tvalid = 1;
            s01_axis_tdata = input_stream_data; //$random; 
            input_stream_data = input_stream_data + 1;
            
            if(!s01_axis_tready) begin
                s01_axis_tvalid = 0; // Deassert valid
            end
        end

        $display("Testbench finished successfully");
        $stop;
    end

endmodule