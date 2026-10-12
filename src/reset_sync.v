`timescale 1ns / 1ps

module reset_sync (
    input wire clk,
    input wire async_rst_n,
    output reg sync_rst_n
);
    reg q;

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            q       <= 1'b0;
            sync_rst_n <= 1'b0;
        end else begin
            q       <= 1'b1;  
            sync_rst_n <= q;
        end
    end

endmodule
