`timescale 1ns / 1ps   

 module async_fifo #(
    parameter WIDTH           = 32,
    parameter DEPTH           = 8                 // must be a power of 2
)(
    // ---- write (source) domain ----
    input  wire              wclk,
    input  wire              wrst_n,     // pre-synchronized to wclk (see header)
    input  wire [WIDTH-1:0]  w_data,
    input  wire              wrt_en,
    output wire               full,

    // ---- read (destination) domain ----
    input  wire              rclk,
    input  wire              rrst_n,     // pre-synchronized to rclk (see header)
    output wire [WIDTH-1:0]  r_data,
    input  wire               rd_en,
    output wire               empty
);

    localparam ADDR_WIDTH     = $clog2(DEPTH);
    //-------------------------------------------------------------------
    // Storage: DEPTH x WIDTH, dual-clock (write port on wclk, read port
    // combinational/look-ahead on rclk's rbin).
    //-------------------------------------------------------------------
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    //-------------------------------------------------------------------
    // Write domain: binary + Gray pointers, one extra MSB (bit ADDR_WIDTH)
    // used purely to disambiguate "wrapped all the way around" (full) from
    // "caught up" (empty) once both pointers are compared in the same domain.
    //-------------------------------------------------------------------
    reg [ADDR_WIDTH:0] wbin, wgray;
    reg [ADDR_WIDTH:0] wq1_rptr, wq2_rptr;   // synchronized read pointer (Gray), in wclk domain
    reg                wfull;

    wire [ADDR_WIDTH:0] wbin_next ;

    wire [ADDR_WIDTH:0] wgray_next = (wbin_next >> 1) ^ wbin_next;   // binary->Gray

    wire wfull_val = (wgray_next == {~wq2_rptr[ADDR_WIDTH:ADDR_WIDTH-1],
                                       wq2_rptr[ADDR_WIDTH-2:0]});
    reg [ADDR_WIDTH:0] rbin, rgray;
    reg [ADDR_WIDTH:0] rq1_wptr, rq2_wptr;   // synchronized write pointer (Gray), in rclk domain
    reg                rempty;

    wire [ADDR_WIDTH:0] rbin_next ;
// = rbin + (rd_en && !rempty);
    wire [ADDR_WIDTH:0] rgray_next = (rbin_next >> 1) ^ rbin_next;   // binary->Gray

    wire rempty_val = (rgray_next == rq2_wptr);
assign wbin_next = (wrt_en && !wfull) ? (wbin + {{ADDR_WIDTH{1'b0}},1'b1}) : wbin;
assign rbin_next = (rd_en && !rempty) ? (rbin + {{ADDR_WIDTH{1'b0}},1'b1}) : rbin;

    // 2-flop synchronizer: read pointer (Gray) crossing into the write domain
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n)
            {wq2_rptr, wq1_rptr} <= 0;
        else
            {wq2_rptr, wq1_rptr} <= {wq1_rptr, rgray};
    end

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin  <= 0;
            wgray <= 0;
            wfull <= 1'b0;
        end else begin
            wbin  <= wbin_next;
            wgray <= wgray_next;
            wfull <= wfull_val;
        end
    end

    always @(posedge wclk) begin
        if (wrt_en && !wfull)
            mem[wbin[ADDR_WIDTH-1:0]] <= w_data;
    end

    assign full = wfull;

    //-------------------------------------------------------------------
    // Read domain: binary + Gray pointers, mirror of the write side.
    //-------------------------------------------------------------------


    // 2-flop synchronizer: write pointer (Gray) crossing into the read domain
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n)
            {rq2_wptr, rq1_wptr} <= 0;
        else
            {rq2_wptr, rq1_wptr} <= {rq1_wptr, wgray};
    end

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin   <= 0;
            rgray  <= 0;
            rempty <= 1'b1;         // FIFO starts empty
        end else begin
            rbin   <= rbin_next;
            rgray  <= rgray_next;
            rempty <= rempty_val;
        end
    end

    assign empty  = rempty;
    assign r_data = mem[rbin[ADDR_WIDTH-1:0]];   // look-ahead: valid combinationally whenever !empty

endmodule
