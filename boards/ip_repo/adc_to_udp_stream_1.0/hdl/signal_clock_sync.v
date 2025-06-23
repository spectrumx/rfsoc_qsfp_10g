///////////////////////////////////////////////////////////////////////////////
// signal_clock_sync.v
//
// Synchronize signal across two clock domains
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

module signal_clock_sync 
(
    input wire clk1_in,
    input wire signal_clk0,
    output wire signal_clk1
);

reg signal_sync1;
reg signal_sync2;

initial begin
    signal_sync1 = 1'b0;
    signal_sync2 = 1'b0;
end

// Two stage reset sync for S01 clock domain
always @(posedge clk1_in) begin
    signal_sync1 <= signal_clk0;
    signal_sync2 <= signal_sync1;
end

assign signal_clk1 = signal_sync2;

endmodule