///////////////////////////////////////////////////////////////////////////////
// reset_clock_sync.v
//
// Synchronize reset across two clock domains
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

module reset_clock_sync 
(
    input wire clk1_in,
    input wire reset_clk0,
    output wire reset_clk1
);

reg reset_sync1;
reg reset_sync2;

initial begin
    reset_sync1 = 1'b0;
    reset_sync2 = 1'b0;
end

// Two stage reset sync for S01 clock domain
always @(posedge clk1_in) begin
    if (reset_clk0) begin
        reset_sync1 <= 1'b1;
        reset_sync2 <= 1'b1;
    end else begin
        reset_sync1 <= 1'b0;
        reset_sync2 <= reset_sync1;
    end
end

assign reset_clk1 = reset_sync2;

endmodule