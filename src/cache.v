

`timescale 1ns / 1ps

module cache #(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 14,
    parameter NUM_LINES      = 8,
    parameter WORDS_PER_LINE = 8
)(
    input  wire                    clk,       // CLK_Fast
    input  wire                    rst_n,

    // ---- CPU side (mirrors cpu_core.v's addr/data_out/wen/ren/hit) ----
    input  wire [ADDR_WIDTH-1:0]   cpu_addr,
    input  wire [DATA_WIDTH-1:0]   cpu_wdata,   // cpu_core's data_out (store data)
    input  wire                    cpu_wen,
    input  wire                    cpu_ren,
    output reg                     hit,
    output wire [DATA_WIDTH-1:0]   data_to_cpu, // wire to BOTH from_sram and from_dm at top level

    // ---- FIFO-2 (fast->slow): this module is the WRITER ----
    output reg  [47:0]             fifo2_w_data,
    output reg                     fifo2_wrt_en,
    input  wire                    fifo2_full,

    // ---- FIFO-1 (slow->fast): this module is the READER ----
    input  wire [45:0]             fifo1_r_data,
    //input wire [DATA_WIDTH-1:0] fifo1_r_data,
    input  wire                    fifo1_empty,
    output reg                     fifo1_rd_en
);

    localparam OFFSET_BITS   = $clog2(WORDS_PER_LINE);
    localparam INDEX_BITS    = $clog2(NUM_LINES);
    localparam TAG_BITS      = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
    //-------------------------------------------------------------------
    // Address breakdown
    //-------------------------------------------------------------------
    wire [TAG_BITS-1:0]    cpu_tag    = cpu_addr[ADDR_WIDTH-1 -: TAG_BITS];
    wire [INDEX_BITS-1:0]  cpu_index  = cpu_addr[OFFSET_BITS +: INDEX_BITS];
    wire [OFFSET_BITS-1:0] cpu_offset = cpu_addr[OFFSET_BITS-1:0];

    //-------------------------------------------------------------------
    // Storage: line data, tag, valid. Empty (all invalid) on reset (2.4).
    //-------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] line_data [0:NUM_LINES-1][0:WORDS_PER_LINE-1];
    reg [TAG_BITS-1:0]   line_tag  [0:NUM_LINES-1];
    reg                  line_valid[0:NUM_LINES-1];

    wire tag_match = (line_tag[cpu_index] == cpu_tag);
    wire is_hit    = tag_match && line_valid[cpu_index];

    //-------------------------------------------------------------------
    // Miss-handling FSM
    //-------------------------------------------------------------------
    localparam [1:0]
        ST_IDLE      = 2'd0,
        ST_MISS_REQ  = 2'd1,   // push the line-fill request onto FIFO-2
        ST_MISS_WAIT = 2'd2,   // pop WORDS_PER_LINE fill words off FIFO-1
        ST_MISS_DONE = 2'd3;   // one-cycle pulse: line valid, hit=1

    reg [1:0] state, next_state;

    // Latched at miss-detection time so the fill sequence is decoupled
    // from whatever the CPU happens to be driving on cpu_addr afterward.
    reg [TAG_BITS-1:0]    req_tag;
    reg [INDEX_BITS-1:0]  req_index;
    reg [OFFSET_BITS-1:0] req_offset;
    reg [OFFSET_BITS-1:0] fill_cnt;

    wire [ADDR_WIDTH-1:0] miss_base_addr = {req_tag, req_index, {OFFSET_BITS{1'b0}}};

    // Read mux: during a completed/in-progress miss for THIS line, use the
    // latched request's index/offset; otherwise track the live CPU address.
    wire [INDEX_BITS-1:0]  sel_index  = (state == ST_IDLE) ? cpu_index  : req_index;
    wire [OFFSET_BITS-1:0] sel_offset = (state == ST_IDLE) ? cpu_offset : req_offset;
    assign data_to_cpu = line_data[sel_index][sel_offset];

    //-------------------------------------------------------------------
    // Combinational: next-state + outputs (fully specified, no latches)
    //-------------------------------------------------------------------
    always @(*) begin
        // defaults
        next_state   = state;
        hit          = 1'b0;
        fifo2_w_data = 48'd0;
        fifo2_wrt_en = 1'b0;
        fifo1_rd_en  = 1'b0;

        case (state)
            ST_IDLE: begin
                if (cpu_ren) begin
                    if (is_hit) begin
                        hit = 1'b1;                       // LOAD hit: done this cycle
                    end else begin
                        next_state = ST_MISS_REQ;          // LOAD miss: start the fill
                    end
                end else if (cpu_wen) begin
                    // Write-through: always forward to memory; cache line
                    // only updated (in the sequential block) if it's a hit.
                    fifo2_w_data = {1'b1, 1'b0, cpu_addr, cpu_wdata};
                    if (!fifo2_full) begin
                        fifo2_wrt_en = 1'b1;
                        hit          = 1'b1;               // accepted this cycle
                    end
                    // else: fifo2 full -> hit stays 0, CPU retries next cycle
                end
            end

            ST_MISS_REQ: begin
                fifo2_w_data = {1'b0, 1'b1, miss_base_addr, {DATA_WIDTH{1'b0}}};
                if (!fifo2_full) begin
                    fifo2_wrt_en = 1'b1;
                    next_state   = ST_MISS_WAIT;
                end
                // else: stall here, retry the push next cycle
            end

            ST_MISS_WAIT: begin
                if (!fifo1_empty) begin
                    fifo1_rd_en = 1'b1;
                    if (fill_cnt == WORDS_PER_LINE-1)
                        next_state = ST_MISS_DONE;
                    // else: stay in ST_MISS_WAIT, fill_cnt advances in seq block
                end
                // else: stall, waiting for the next fill word
            end

            ST_MISS_DONE: begin
                hit        = 1'b1;      // one-cycle pulse: line is now valid
                next_state = ST_IDLE;
            end

            default: next_state = ST_IDLE;
        endcase
    end

    //-------------------------------------------------------------------
    // Sequential: state, latched miss request, line storage, valid bits
    //-------------------------------------------------------------------
    integer li;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            fill_cnt <= {OFFSET_BITS{1'b0}};
            for (li = 0; li < NUM_LINES; li = li + 1)
                line_valid[li] <= 1'b0;         // cache empty on reset (2.4)
        end else begin
            state <= next_state;

            case (state)
                ST_IDLE: begin
                    if (cpu_ren && !is_hit) begin
                        // latch the missed request for the fill sequence
                        req_tag    <= cpu_tag;
                        req_index  <= cpu_index;
                        req_offset <= cpu_offset;
                        fill_cnt   <= {OFFSET_BITS{1'b0}};
                    end else if (cpu_wen && !fifo2_full && is_hit) begin
                        // write-through: update the line on a store HIT only
                        line_data[cpu_index][cpu_offset] <= cpu_wdata;
                    end
                end

                ST_MISS_WAIT: begin
                    if (!fifo1_empty) begin
                        line_data[req_index][fill_cnt] <= fifo1_r_data[DATA_WIDTH-1:0];
                        if (fill_cnt == WORDS_PER_LINE-1) begin
                            line_tag[req_index]   <= req_tag;
                            line_valid[req_index] <= 1'b1;   // whole line now valid
                        end else begin
                            fill_cnt <= fill_cnt + 1'b1;
                        end
                    end
                end

                //default: begin
		//	state <= ST_IDLE;  
		//end  // ST_MISS_REQ, ST_MISS_DONE: no storage updates
            endcase
        end
    end

endmodule
