`timescale 1ns / 1ps

module cache_dm_control #(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 14,
    parameter WORDS_PER_LINE = 8 ,
    parameter FIFO2_WIDTH   = 1 + 1 + ADDR_WIDTH + DATA_WIDTH,  // wen,ren,addr,data = 48
    parameter FIFO1_WIDTH   = ADDR_WIDTH + DATA_WIDTH                                
)(
    input  wire                      clk,          // CLK_Slow
    input  wire                      rst_n,

    // ---- FIFO-2 (fast->slow): pop the CPU's pending request ----
    input  wire [FIFO2_WIDTH-1:0]    fifo2_r_data,
    input  wire                      fifo2_empty,
    output wire                      fifo2_rd_en,

    // ---- data_mem.v interface ----
    output wire [ADDR_WIDTH-1:0]     dm_addr,
    output wire [DATA_WIDTH-1:0]     dm_wdata,
    output wire                      dm_wen,
    output wire                      dm_ren,
    input  wire [ADDR_WIDTH-1:0]     dm_addr_echo,   // data_mem's addr_to_sram
    input  wire [DATA_WIDTH-1:0]     dm_rdata,        // data_mem's data_to_sram / data_to_cpu (same value)
    input  wire                      dm_data_valid,

    // ---- FIFO-1 (slow->fast): push the cache-fill payload ----
    output wire [FIFO1_WIDTH-1:0]    fifo1_w_data,
    output wire                      fifo1_wrt_en,
    input  wire                      fifo1_full
);
/*
    localparam FIFO2_WIDTH   = 1 + 1 + ADDR_WIDTH + DATA_WIDTH;  // wen,ren,addr,data = 48
    localparam FIFO1_WIDTH   = ADDR_WIDTH + DATA_WIDTH; 
*/           // addr,data       = 46
    localparam BURST_CNT_W   = $clog2(WORDS_PER_LINE);
    //-------------------------------------------------------------------
    // FSM state encoding
    //-------------------------------------------------------------------
    localparam [1:0]
        S_IDLE  = 2'd0,   // waiting for a request on FIFO-2
        S_ISSUE = 2'd1,   // drive the request to data_mem for one cycle
        S_WAIT  = 2'd2,   // wait for data_mem's response
        S_PUSH  = 2'd3;   // push the fill into FIFO-1 (LOAD only)

    reg [1:0] state, next_state;

    //-------------------------------------------------------------------
    // Captured request fields (latched out of FIFO-2 at pop time)
    //-------------------------------------------------------------------
    reg                     req_wen;
    reg                     req_ren;
    //reg [ADDR_WIDTH-1:0]    req_addr;
    reg [DATA_WIDTH-1:0]    req_data;

    // Burst state for LOAD-miss line fills (unused/held at 0 for STOREs).
    reg [ADDR_WIDTH-1:0]    burst_addr;    // current word address within the burst
    reg [BURST_CNT_W-1:0]   burst_cnt;     // words pushed so far, 0..WORDS_PER_LINE-1

    // Combinational: next-state logic (fully specified, no latches)
    //-------------------------------------------------------------------
    always @(*) begin
        next_state = state;   // default: hold
        case (state)
            S_IDLE: begin
                if (!fifo2_empty)
                    next_state = S_ISSUE;
            end

            S_ISSUE: begin
                next_state = S_WAIT;   // request is driven for exactly this one cycle
            end

            S_WAIT: begin
                if (dm_data_valid)
                    next_state = req_ren ? S_PUSH : S_IDLE;
                else
                    next_state = S_WAIT;
            end

            S_PUSH: begin
                if (!fifo1_full) begin
                    if (burst_cnt == WORDS_PER_LINE-1)
                        next_state = S_IDLE;    // burst complete
                    else
                        next_state = S_ISSUE;   // more words in this line -- loop
                end else begin
                    next_state = S_PUSH;        // stall until FIFO-1 has room
                end
            end

            default: next_state = S_IDLE;
        endcase
    end

    //-------------------------------------------------------------------
    // Combinational: pulse-style outputs, pure functions of state
    //-------------------------------------------------------------------
    assign fifo2_rd_en  = (state == S_IDLE)  && !fifo2_empty;
    assign dm_wen       = (state == S_ISSUE) &&  req_wen;
    assign dm_ren       = (state == S_ISSUE) &&  req_ren;
    assign fifo1_wrt_en = (state == S_PUSH)  && !fifo1_full;

    assign dm_addr       = burst_addr;
    assign dm_wdata      = req_data;
    assign fifo1_w_data = {dm_addr_echo, dm_rdata};


    //-------------------------------------------------------------------
    // Sequential: state register, request capture, timeout counter
    //-------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            req_wen         <= 1'b0;
            req_ren         <= 1'b0;
            //req_addr        <= {ADDR_WIDTH{1'b0}};
            req_data        <= {DATA_WIDTH{1'b0}};
            burst_addr      <= {ADDR_WIDTH{1'b0}};
            burst_cnt       <= {BURST_CNT_W{1'b0}};

        end else begin
            state <= next_state;
            // Capture the request the same cycle it's popped off FIFO-2,
            // and start the burst address/counter at the request's address.
            if (state == S_IDLE && !fifo2_empty) begin
                req_wen    <= fifo2_r_data[FIFO2_WIDTH-1];
                req_ren    <= fifo2_r_data[FIFO2_WIDTH-2];
                //req_addr   <= fifo2_r_data[DATA_WIDTH +: ADDR_WIDTH];
                req_data   <= fifo2_r_data[DATA_WIDTH-1:0];
                //burst_addr <= fifo2_r_data[DATA_WIDTH +: ADDR_WIDTH];
                //burst_cnt  <= {BURST_CNT_W{1'b0}};
            end
            if (state == S_IDLE && !fifo2_empty) begin
                burst_addr <= fifo2_r_data[DATA_WIDTH +: ADDR_WIDTH];
                burst_cnt  <= {BURST_CNT_W{1'b0}};
	    end else 
            // Advance the burst on the loop-back from S_PUSH: one more word
            // pushed, move to the next address in the line.
            if (state == S_PUSH && !fifo1_full && (burst_cnt != WORDS_PER_LINE-1)) begin
                burst_addr <= burst_addr + 1'b1;
                burst_cnt  <= burst_cnt + 1'b1;
            end

        end
    end

endmodule

