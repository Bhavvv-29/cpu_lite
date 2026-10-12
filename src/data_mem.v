//data_mem 16384 - slow clk 

`timescale 1ns / 1ps


module data_mem #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 14
)(
    input wire clk,   
    input wire rst_n,
    //req from cache_dm_control 
    input wire [ADDR_WIDTH-1:0] addr_from_cpu,
    input wire [DATA_WIDTH-1:0] data_from_cpu,    // write data
    input wire wen,
    input wire ren,
    //response - sent to cache_dm_control fifo1
    output wire [ADDR_WIDTH-1:0] addr_to_sram,     // request address
    output wire [DATA_WIDTH-1:0] data_to_sram,     // read data
    output wire data_valid        // ren OR wen
);

    localparam MEM_DEPTH = (1 << ADDR_WIDTH);
    reg [DATA_WIDTH-1:0] d_mem [0:MEM_DEPTH-1];
    reg [ADDR_WIDTH-1:0] addr_reg;
    reg [DATA_WIDTH-1:0] rdata_reg;
    reg req_d;    

    always @(posedge clk) begin
        if (!rst_n) begin
            addr_reg  <= {ADDR_WIDTH{1'b0}};
            rdata_reg <= {DATA_WIDTH{1'b0}};
            req_d     <= 1'b0;
        end else begin
            req_d <= ren | wen; 
            if (wen)
                d_mem[addr_from_cpu] <= data_from_cpu;  
	else if(ren)
		begin
		    addr_reg  <= addr_from_cpu;
		    rdata_reg <= d_mem[addr_from_cpu];  
		end
        end
    end
    assign addr_to_sram = addr_reg;
    assign data_to_sram = rdata_reg;
    assign data_valid   = req_d;
endmodule


