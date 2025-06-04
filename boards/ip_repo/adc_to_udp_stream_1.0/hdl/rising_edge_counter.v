///////////////////////////////////////////////////////////////////////////////
// rising_edge_counter.v
//
// Count rising edges of input clock.
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

module rising_edge_counter #
(
    parameter integer COUNTER_WIDTH = 64
)
(
    input wire clk_in,
    input wire resetn,
    output reg [COUNTER_WIDTH-1 : 0] edge_count
);

always @(posedge clk_in or negedge resetn) begin
    if (!resetn) begin
        edge_count <= {COUNTER_WIDTH{1'b0}}; // Reset the counter
    end else begin
        edge_count <= edge_count + 1; // Increment the counter on each rising edge
    end
end

endmodule