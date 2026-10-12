//progm mem 4096 - fast clk 

 `timescale 1ns / 1ps

module progm_mem #(
    parameter DATA_WIDTH = 32,
    parameter PC_WIDTH   = 12
)(
    input wire clk,    
    input wire rst_n,
    input wire [PC_WIDTH-1:0] pc,
    output wire [DATA_WIDTH-1:0] instr
);
	localparam integer MEM_DEPTH = (1<<PC_WIDTH);
	reg [DATA_WIDTH-1:0] p_mem [0:MEM_DEPTH-1];

	reg [DATA_WIDTH-1:0] instr_reg;

always @(posedge clk ) begin
	if (!rst_n)
		instr_reg <= {DATA_WIDTH{1'b0}};
	else
		instr_reg <= p_mem[pc];
end

assign instr = instr_reg;

endmodule


