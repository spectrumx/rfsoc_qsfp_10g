`timescale 1 ns / 1 ps

module udp_stream_v1_0_tb;

    parameter integer C_S00_AXI_DATA_WIDTH	= 32;
    parameter integer C_S00_AXI_ADDR_WIDTH	= 5;

    // Parameters of Axi Master Bus Interface M00_AXIS
    parameter integer C_M00_AXIS_TDATA_WIDTH = 64;
    parameter integer C_M00_AXIS_TKEEP_WIDTH = 8;

    // Clock and Reset signals for AXI4-Lite (S00_AXI)
    reg s00_axi_aclk;
    reg s00_axi_aresetn;

    // AXI4-Stream Interface signals
    reg m00_axis_aclk;
    reg m00_axis_aresetn;

    // Signals for AXI4-Lite (S00_AXI)
    wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr;
    wire [2 : 0] s00_axi_awprot;
    wire s00_axi_awvalid;
    reg s00_axi_awready;
    wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata;
    wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb;
    wire s00_axi_wvalid;
    reg s00_axi_wready;
    reg [1 : 0] s00_axi_bresp;
    reg s00_axi_bvalid;
    wire s00_axi_bready;
    wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr;
    wire [2 : 0] s00_axi_arprot;
    wire s00_axi_arvalid;
    reg s00_axi_arready;
    reg [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata;
    reg [1 : 0] s00_axi_rresp;
    reg s00_axi_rvalid;
    wire s00_axi_rready;

    // AXI4-Stream Interface signals
    wire m00_axis_tvalid;
    wire [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata;
    wire [C_M00_AXIS_TKEEP_WIDTH-1 : 0] m00_axis_tkeep;
    wire m00_axis_tlast;
    wire m00_axis_tuser;
    reg m00_axis_tready;

    // Instantiate the UDP Stream module
    udp_stream_v1_0 #(
        .C_S00_AXI_DATA_WIDTH(32),
        .C_S00_AXI_ADDR_WIDTH(5),
        .C_M00_AXIS_TDATA_WIDTH(64)
    ) uut (
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

        .m00_axis_aclk(m00_axis_aclk),
        .m00_axis_aresetn(m00_axis_aresetn),
        .m00_axis_tvalid(m00_axis_tvalid),
        .m00_axis_tdata(m00_axis_tdata),
        .m00_axis_tkeep(m00_axis_tkeep),
        .m00_axis_tuser(m00_axis_tuser),
        .m00_axis_tlast(m00_axis_tlast),
        .m00_axis_tready(m00_axis_tready)
    );

    // Clock generation for AXI4-Lite (S00_AXI) (100 MHz = 10 ns period)
    initial begin
        s00_axi_aclk = 0;
        forever #5 s00_axi_aclk = ~s00_axi_aclk;  // Toggle every 5 ns for a 10 ns period
    end

    // Clock generation for AXI4-Stream (M00_AXIS) (100 MHz = 10 ns period)
    initial begin
        m00_axis_aclk = 0;
        forever #5 m00_axis_aclk = ~m00_axis_aclk;  // Toggle every 5 ns for a 10 ns period
    end

    // Reset generation
    initial begin
        s00_axi_aresetn = 1;
        m00_axis_aresetn = 0;
        #20 m00_axis_aresetn = 1;  // Deassert reset after 20 ns
    end

    // Test logic
    integer i;
    bit tvalid_high = 0;

    initial begin
        // Initialize tready to low
        m00_axis_tready = 1'b0;
        i = 0;

        // Wait for reset deassertion
        @(posedge m00_axis_aresetn);

        // Test the transmission of one UDP packet
        repeat (4) begin
            @(posedge m00_axis_aclk);
            if (m00_axis_tvalid) begin
                tvalid_high = 1;  // Set flag that m00_axis_tvalid was high

                #1;  // Small delay to capture tdata value before it changes

                m00_axis_tready = 1'b1;  // Acknowledge the data by asserting tready
                i = i + 1;
            end else begin
                m00_axis_tready = 1'b0;  // Deassert tready to simulate a delay in processing
            end
        end

        // Final check after the data has been processed
        assert(tvalid_high) else $error("m00_axis_tvalid never went high");

        // Finish simulation after 100ms (100MHz clock)
        #102000000; 

        $display("Testbench finished successfully");
        $stop;
    end

endmodule