//cpu core 
//includes optional functions 
//
`timescale 1ns / 1ps
module cpu_core #(
    parameter DATA_WIDTH = 32,
    parameter PC_WIDTH = 12,
    parameter ADDR_WIDTH = 14
)(
    input wire clk,
    input wire rst_n,

    //instr from progm mem 
    input wire [DATA_WIDTH-1:0] instr,

    // data path from cache (hit) / memory-side fallback (miss)
    input wire [DATA_WIDTH-1:0] from_dm,
    input wire [DATA_WIDTH-1:0] from_sram,
    input wire hit,

    // decoded-field observability (debug/waveform use)
   /* output wire [7:0] opr,
    output wire [3:0] rout,
    output wire [3:0] op1,
    output wire [3:0] op2,
    output wire [11:0] addr_imm,*/

    // memory-side request
    output wire [ADDR_WIDTH-1:0] addr,
    output wire [DATA_WIDTH-1:0] data_out,

    output wire [PC_WIDTH-1:0] pc,

    output wire wen,
    output wire ren
    //output wire halted
);

//opcodes 
    localparam [7:0]
        OP_NOP = 8'h00,
        OP_LOAD = 8'h01,
        OP_LOAD_IND = 8'h02,
        OP_LOAD_IMM = 8'h03,
        OP_STORE = 8'h04,
        OP_STORE_IND = 8'h05,
        OP_ADD = 8'h06,
        OP_SUB = 8'h07,
        OP_MUL = 8'h08,
        OP_AND = 8'h09,
        OP_OR = 8'h0A,
        OP_NOT = 8'h0B,
        OP_CMP = 8'h0C,
        OP_EQ = 8'h0D,
        OP_JMP = 8'h0E,
        OP_JMP_IF = 8'h0F,
	OP_XOR = 8'h10,//op
        OP_SHL = 8'h11,
        OP_SHR = 8'h12,
        OP_SAR = 8'h13,
	OP_ROL = 8'h14,//op
	OP_ROR = 8'h15,//op
        OP_ADDI = 8'h16,
        OP_SUBI = 8'h17,
	OP_ANDI= 8'h18,//op
	OP_ORI= 8'h19,//op
	OP_XORI= 8'h1A,//op
	OP_MOV= 8'h1B,//op
	OP_SLT= 8'h1C,//op
	OP_SLTU= 8'h1D,//op
	OP_LUI= 8'h1E,//op
        OP_BEQ = 8'h20,
        OP_BNE = 8'h21,
        OP_BLT = 8'h22,
        OP_BGE = 8'h23,
	OP_BLTU= 8'h24,//op
	OP_BGEU= 8'h25,//op
	OP_JMP_REG= 8'h26,//op
        OP_HALT = 8'hFF;

	//FSM states 
    localparam [2:0]
        ST_FETCH     = 3'd0,
        ST_DECODE    = 3'd1,
        ST_EXECUTE   = 3'd2,
        ST_MEMORY    = 3'd3,
        ST_WRITEBACK = 3'd4,
        ST_HALT      = 3'd5;

    reg [2:0] state, next_state;

    //instruction decoder 
    wire [7:0]  opcode = instr[31:24];
    wire [3:0]  rd     = instr[23:20];
    wire [3:0]  rs1    = instr[19:16];
    wire [3:0]  rs2    = instr[15:12];
    wire [11:0] imm    = instr[11:0];
/*

    assign opr      = opcode;
    assign rout     = rd;
    assign op1      = rs1;
    assign op2      = rs2;
    assign addr_imm = imm;*/

    //-------------------------------------------------------------------
    // Register file (R0..R15, all normal -- no hard-wired zero)
    //-------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] registers [0:15];

    wire [DATA_WIDTH-1:0] op1_data   = registers[rs1];
    wire [DATA_WIDTH-1:0] op2_data   = registers[rs2];
    wire [DATA_WIDTH-1:0] store_data = registers[rd];   // Rd is also STORE's source reg
    // PSR (Z N C V)
    reg [3:0] psr;

    wire flag_z = psr[0];
    wire flag_n = psr[1];
    wire flag_c = psr[2];
    wire flag_v = psr[3];

    // PC
    reg [PC_WIDTH-1:0] pc_reg;
    assign pc = pc_reg;

    // ALU input mux
    reg [DATA_WIDTH-1:0] alu_a, alu_b;

    always @(*) begin
        alu_a = op1_data;
        case (opcode)
            OP_ADDI, OP_SUBI:
                alu_b = {{(DATA_WIDTH-12){imm[11]}}, imm};        // sign-extended immediate
	    OP_ANDI, OP_ORI, OP_XORI :
		alu_b = {{(DATA_WIDTH-12){imm[11]}},imm}; 
	OP_SHL, OP_SHR, OP_SAR , OP_ROL,OP_ROR:
                alu_b = {{(DATA_WIDTH-5){1'b0}}, op2_data[4:0]};  // shift amount = Rs2's VALUE, not the field
            default:
                alu_b = op2_data;
        endcase
    end

    // ALU
    reg [DATA_WIDTH-1:0] alu_result;
    reg alu_carry;
    reg alu_overflow;
    reg [(DATA_WIDTH*2)-1:0]mul_result ;
    reg [DATA_WIDTH:0] sub_result ;

    always @(*) begin
        case (opcode)
            OP_ADD, OP_ADDI: begin
                {alu_carry, alu_result} = alu_a + alu_b;
                alu_overflow = (~(alu_a[DATA_WIDTH-1] ^ alu_b[DATA_WIDTH-1])) &
                               (alu_result[DATA_WIDTH-1] ^ alu_a[DATA_WIDTH-1]);
            end

            OP_SUB, OP_SUBI, OP_CMP: begin
                sub_result   = alu_a - alu_b;
		alu_result = sub_result [DATA_WIDTH-1:0];
                alu_carry    = (alu_a >= alu_b);                 // spec: C=1 means "no borrow"
                alu_overflow = (alu_a[DATA_WIDTH-1] ^ alu_b[DATA_WIDTH-1]) &
                               (alu_result[DATA_WIDTH-1] ^ alu_a[DATA_WIDTH-1]);
            end

            OP_MUL: begin
                mul_result   = alu_a * alu_b;                    // low DATA_WIDTH bits kept automatically
		alu_result = mul_result[DATA_WIDTH-1:0];
                alu_carry    = 1'b0;
                alu_overflow = 1'b0;
            end

            OP_AND: begin
                alu_result   = alu_a & alu_b;
                alu_carry    = 1'b0;
                alu_overflow = 1'b0;
            end

            OP_OR: begin
                alu_result   = alu_a | alu_b;
                alu_carry    = 1'b0;
                alu_overflow = 1'b0;
            end

            OP_NOT: begin
                alu_result   = ~alu_a;
                alu_carry    = 1'b0;
                alu_overflow = 1'b0;
            end

            OP_EQ: begin
                alu_result   = (alu_a == alu_b) ? {{(DATA_WIDTH-1){1'b0}}, 1'b1} : {DATA_WIDTH{1'b0}};
                alu_carry    = 1'b0;
                alu_overflow = 1'b0;
            end

            OP_SHL: begin
                alu_result   = alu_a << alu_b[4:0];
                alu_carry    = 1'b0;
                alu_overflow = 1'b0;
            end

            OP_SHR: begin
                alu_result   = alu_a >> alu_b[4:0];               // logical (zero-fill)
                alu_carry    = 1'b0;
                alu_overflow = 1'b0;
            end

            OP_SAR: begin
                alu_result   = $signed(alu_a) >>> alu_b[4:0];     // arithmetic (sign-fill)
                alu_carry    = 1'b0;
                alu_overflow = 1'b0;
            end
	    OP_XOR : begin 
	    	alu_result = alu_a ^ alu_b ;
		alu_carry = 1'b0;
		alu_overflow = 1'b0;
    	    end 

	    OP_ROL : begin
		  alu_result = (alu_a << alu_b[4:0])| (alu_a >> (DATA_WIDTH- alu_b[4:0]));
		  alu_carry  = 1'b0;
		  alu_overflow = 1'b0;

    	    end

	    OP_ROR : begin 
	    	alu_result = (alu_a >> alu_b [4:0] )| (alu_a << (DATA_WIDTH - alu_b[4:0]));
		alu_carry = 1'b0;
		alu_overflow = 1'b0;
	    end 

	    OP_ANDI : begin
		  alu_result = alu_a & alu_b;
		  alu_carry = 1'b0;
		  alu_overflow = 1'b0;
    	    end 
	    OP_ORI: begin 
	    	alu_result = alu_a | alu_b ;
		alu_carry = 1'b0;
		alu_overflow = 1'b0;
    	    end

	    OP_XORI: begin 
	    	alu_result = alu_a ^ alu_b ;
		alu_carry = 1'b0;
		alu_overflow = 1'b0;
    	    end 

	    OP_MOV: begin
		   alu_result = alu_a ;
		   alu_carry = 1'b0;
		   alu_overflow = 1'b0;

    	    end 
	    OP_SLT : begin 
	         alu_result = ($signed (alu_a) < $signed (alu_b))?{{(DATA_WIDTH-1){1'b0}},1'b1} : {DATA_WIDTH {1'b0}};
		 alu_carry = 1'b0;
		 alu_overflow = 1'b0;
    	    end 

	    OP_SLTU : begin 
	    	alu_result = (alu_a < alu_b )?{{(DATA_WIDTH-1){1'b0}},1'b1}:{DATA_WIDTH{1'b0}};
		alu_carry = 1'b0;
		alu_overflow = 1'b0;
     	    end



            default: begin
                alu_result   = {DATA_WIDTH{1'b0}};
                alu_carry    = 1'b0;
                alu_overflow = 1'b0;
            end
        endcase
    end

    // PSR-write and register-write enables (pure decode, no state dependence)
    reg psr_write;
    always @(*) begin
        case (opcode)
            OP_ADD, OP_SUB, OP_ADDI, OP_SUBI, OP_MUL,
            OP_AND, OP_OR, OP_NOT, OP_CMP, OP_EQ,
            OP_SHL, OP_SHR, OP_SAR, 
	    OP_XOR , OP_ROL , OP_ROR , OP_ANDI, OP_ORI, OP_XORI,
	    OP_SLT , OP_SLTU :
                psr_write = 1'b1;
            default:
                psr_write = 1'b0;
        endcase
    end

    reg reg_write;
    always @(*) begin
        case (opcode)
            OP_LOAD, OP_LOAD_IND, OP_LOAD_IMM,
            OP_ADD, OP_SUB, OP_ADDI, OP_SUBI, OP_MUL,
            OP_AND, OP_OR, OP_NOT, OP_EQ,
            OP_SHL, OP_SHR, OP_SAR,
	    OP_XOR, OP_ROL, OP_ROR , OP_ANDI , OP_ORI, OP_XORI, 
	    OP_MOV, OP_SLT, OP_SLTU ,OP_LUI:
                reg_write = 1'b1;
            default:
                reg_write = 1'b0;      // includes CMP (flags only, no writeback), STORE*, branches, JMP*, HALT, NOP
        endcase
    end

    // Address mux (to cache.v)
    reg [ADDR_WIDTH-1:0] address_mux_out;
    always @(*) begin
        case (opcode)
            OP_LOAD, OP_STORE:
                address_mux_out = {{(ADDR_WIDTH-12){1'b0}}, imm};        // direct: first 4K only
            OP_LOAD_IND:
                address_mux_out = op1_data[ADDR_WIDTH-1:0];               // full 16K range
            OP_STORE_IND:
                address_mux_out = op2_data[ADDR_WIDTH-1:0];               // full 16K range
            default:
                address_mux_out = {ADDR_WIDTH{1'b0}};
        endcase
    end

    assign addr     = address_mux_out;
    assign data_out = store_data;

    // Data-in mux (cache hit vs. memory-side fallback)
    wire [DATA_WIDTH-1:0] data_mux_out = hit ? from_sram : from_dm;

    // Writeback mux
    reg [DATA_WIDTH-1:0] writeback_data;
    always @(*) begin
        case (opcode)
            OP_LOAD, OP_LOAD_IND:
                writeback_data = data_mux_out;
            OP_LOAD_IMM:
                writeback_data = {{(DATA_WIDTH-12){1'b0}}, imm};   
	    OP_LUI : writeback_data = {imm , {(DATA_WIDTH-12){1'b0}}};
	default:
                writeback_data = alu_result;
        endcase
    end

    // Memory request strobes -- asserted only during ST_MEMORY
    assign ren = (state == ST_MEMORY) && ((opcode == OP_LOAD) || (opcode == OP_LOAD_IND));
    assign wen = (state == ST_MEMORY) && ((opcode == OP_STORE) || (opcode == OP_STORE_IND));

    // Branch/jump resolution
    reg branch_taken;
    always @(*) begin
        case (opcode)
            OP_JMP:    branch_taken = 1'b1;
            OP_JMP_IF: branch_taken = (op1_data != {DATA_WIDTH{1'b0}});
            OP_BEQ:    branch_taken = flag_z;
            OP_BNE:    branch_taken = !flag_z;
            OP_BLT:    branch_taken = flag_n ^ flag_v;                   // signed <
            OP_BGE:    branch_taken = !(flag_n ^ flag_v);                // signed >=
	    OP_BLTU : branch_taken = !flag_c ;
	    OP_BGEU : branch_taken = flag_c;
	    OP_JMP_REG : branch_taken = 1'b1;
            default:   branch_taken = 1'b0;
        endcase
    end

    reg[PC_WIDTH-1:0] branch_target ;
    always @(*) begin 
	    case (opcode) 
		    OP_JMP_REG : branch_target = op1_data[PC_WIDTH-1:0];
		    default : branch_target = imm[PC_WIDTH-1:0];
	    endcase 
    end 
    
    // Next-PC computation (no inc_pc port -- always advance unless taken)
    wire [PC_WIDTH-1:0] next_pc = (opcode == OP_JMP_REG)?branch_target : branch_taken ? imm[PC_WIDTH-1:0] : (pc_reg + {{(PC_WIDTH-1){1'b0}}, 1'b1});

    //-------------------------------------------------------------------
    // FSM: next-state logic
    //-------------------------------------------------------------------
    always @(*) begin
        case (state)
            ST_FETCH:
                next_state = ST_DECODE;

            ST_DECODE:
                next_state = ST_EXECUTE;

            ST_EXECUTE: begin
                case (opcode)
                    OP_LOAD, OP_LOAD_IND, OP_STORE, OP_STORE_IND:
                        next_state = ST_MEMORY;
                    OP_HALT:
                        next_state = ST_HALT;
                    default:
                        next_state = ST_WRITEBACK;
                endcase
            end

            ST_MEMORY:
                next_state = hit ? ST_WRITEBACK : ST_MEMORY;

            ST_WRITEBACK:
                next_state = ST_FETCH;

            ST_HALT:
                next_state = ST_HALT;

            default:
                next_state = ST_FETCH;
        endcase
    end

   // assign halted = (state == ST_HALT);

    // Sequential: state register, PC, register file, PSR
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= ST_FETCH;
            pc_reg <= {PC_WIDTH{1'b0}};
            psr    <= 4'b0000;
            for (i = 0; i < 16; i = i + 1)
                registers[i] <= {DATA_WIDTH{1'b0}};
        end else begin
            state <= next_state;

            // Instruction fully completes before PC moves on.
            if (state == ST_WRITEBACK) begin
                pc_reg <= next_pc;

                if (reg_write)
                    registers[rd] <= writeback_data;

                if (psr_write) begin
                    psr[0] <= (alu_result == {DATA_WIDTH{1'b0}});
                    psr[1] <= alu_result[DATA_WIDTH-1];
                    psr[2] <= alu_carry;
                    psr[3] <= alu_overflow;
                end
            end
        end
    end

endmodule

