`timescale 1ns / 1ps

//=============================================================================
// CPU-Lite V2 TOP MODULE
//
// FAST CLOCK DOMAIN
// -----------------
//      reset_sync
//          |
//      progm_mem
//          |
//      cpu_core
//          |
//        cache
//          |
//       FIFO-2
//      FAST -> SLOW
//
// SLOW CLOCK DOMAIN
// -----------------
//       FIFO-2
//          |
//   cache_dm_control
//          |
//      data_mem
//          |
//       FIFO-1
//      SLOW -> FAST
//          |
//        cache
//
// No timeout logic.
// No program-file parameter.
//
// Debug signals (halted, pc_debug, opr_debug, ...) are INTERNAL wires only,
// not ports. Reach them from a testbench via hierarchical reference,
// e.g. dut.halted, dut.pc_debug.
//=============================================================================

module cpu_lite_top #(
    parameter DATA_WIDTH     = 32,
    parameter PC_WIDTH       = 12,
    parameter ADDR_WIDTH     = 14,
    parameter NUM_LINES      = 8,
    parameter WORDS_PER_LINE = 8,
    parameter FIFO_DEPTH     = 8
)(
    input wire CLK_Fast,
    input wire CLK_Slow,
    input wire RSTn
);


    localparam FIFO2_WIDTH =1 + 1 + ADDR_WIDTH + DATA_WIDTH;
    localparam FIFO1_WIDTH =ADDR_WIDTH + DATA_WIDTH;

    //=========================================================================
    // DEBUG SIGNALS (internal wires -- no longer ports)
    //=========================================================================

    /*wire                halted;
    wire [PC_WIDTH-1:0] pc_debug;
    wire [7:0]          opr_debug;
    wire [3:0]          rout_debug;
    wire [3:0]          op1_debug;
    wire [3:0]          op2_debug;
    wire [11:0]         addr_imm_debug;*/


    //=========================================================================
    // RESET SIGNALS
    //=========================================================================

    wire fast_rst_n;
    wire slow_rst_n;


    //=========================================================================
    // FAST DOMAIN SIGNALS
    //=========================================================================

    // Program memory -> CPU
    wire [DATA_WIDTH-1:0] cpu_instr;
    wire [PC_WIDTH-1:0]   cpu_pc;


    // CPU -> Cache
    wire [ADDR_WIDTH-1:0] cpu_addr;
    wire [DATA_WIDTH-1:0] cpu_data_out;

    wire cpu_wen;
    wire cpu_ren;


    // Cache -> CPU
    wire [DATA_WIDTH-1:0] cache_data_to_cpu;
    wire                  cache_hit;


    //=========================================================================
    // FIFO-2 SIGNALS
    //
    // FAST -> SLOW
    //
    // { wen, ren, address, data }
    //=========================================================================

    wire [FIFO2_WIDTH-1:0] fifo2_w_data;
    wire                   fifo2_wrt_en;
    wire                   fifo2_full;

    wire [FIFO2_WIDTH-1:0] fifo2_r_data;
    wire                   fifo2_rd_en;
    wire                   fifo2_empty;


    //=========================================================================
    // FIFO-1 SIGNALS
    //
    // SLOW -> FAST
    //
    // { address, data }
    //=========================================================================

    wire [FIFO1_WIDTH-1:0] fifo1_w_data;
    wire                   fifo1_wrt_en;
    wire                   fifo1_full;

    wire [FIFO1_WIDTH-1:0] fifo1_r_data;
    //wire [DATA_WIDTH-1:0] fifo1_r_data;
    wire                   fifo1_rd_en;
    wire                   fifo1_empty;


    //=========================================================================
    // DATA MEMORY INTERFACE
    //=========================================================================

    wire [ADDR_WIDTH-1:0] dm_addr;
    wire [DATA_WIDTH-1:0] dm_wdata;

    wire dm_wen;
    wire dm_ren;

    wire [ADDR_WIDTH-1:0] dm_addr_echo;
    wire [DATA_WIDTH-1:0] dm_rdata;

    wire dm_data_valid;


    //=========================================================================
    // RESET SYNCHRONIZERS
    //=========================================================================

    // Fast clock domain reset
    reset_sync u_reset_sync_fast (
        .clk         (CLK_Fast),
        .async_rst_n (RSTn),
        .sync_rst_n  (fast_rst_n)
    );


    // Slow clock domain reset
    reset_sync u_reset_sync_slow (
        .clk         (CLK_Slow),
        .async_rst_n (RSTn),
        .sync_rst_n  (slow_rst_n)
    );


    //=========================================================================
    // PROGRAM MEMORY
    //
    // 4096 x 32
    //
    // No PROGRAM_FILE is used.
    //=========================================================================

    progm_mem #(
        .DATA_WIDTH (DATA_WIDTH),
        .PC_WIDTH   (PC_WIDTH)
        //.MEM_DEPTH  (4096)
    ) u_progm_mem (
        .clk   (CLK_Fast),
        .rst_n (fast_rst_n),

        .pc    (cpu_pc),
        .instr (cpu_instr)
    );


    //=========================================================================
    // CPU CORE
    //=========================================================================

    cpu_core #(
        .DATA_WIDTH (DATA_WIDTH),
        .PC_WIDTH   (PC_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_cpu_core (
        .clk   (CLK_Fast),
        .rst_n (fast_rst_n),

        // Instruction
        .instr (cpu_instr),

        // Cache response
        .from_dm   (cache_data_to_cpu),
        .from_sram (cache_data_to_cpu),
        .hit       (cache_hit),

        // Debug
/*
        .opr      (opr_debug),
        .rout     (rout_debug),
        .op1       (op1_debug),
        .op2       (op2_debug),
        .addr_imm (addr_imm_debug),*/

        // Memory interface
        .addr     (cpu_addr),
        .data_out (cpu_data_out),

        // PC
        .pc       (cpu_pc),

        // Memory controls
        .wen      (cpu_wen),
        .ren      (cpu_ren)

        // Halt
        //.halted   (halted)
    );


    //=========================================================================
    // L1 CACHE
    //=========================================================================

    cache #(
        .DATA_WIDTH     (DATA_WIDTH),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .NUM_LINES      (NUM_LINES),
        .WORDS_PER_LINE (WORDS_PER_LINE)
    ) u_cache (
        .clk   (CLK_Fast),
        .rst_n (fast_rst_n),

        // CPU -> Cache
        .cpu_addr  (cpu_addr),
        .cpu_wdata (cpu_data_out),
        .cpu_wen   (cpu_wen),
        .cpu_ren   (cpu_ren),

        // Cache -> CPU
        .hit         (cache_hit),
        .data_to_cpu (cache_data_to_cpu),

        // Cache -> FIFO-2
        .fifo2_w_data (fifo2_w_data),
        .fifo2_wrt_en (fifo2_wrt_en),
        .fifo2_full   (fifo2_full),

        // FIFO-1 -> Cache
        .fifo1_r_data (fifo1_r_data),
        .fifo1_empty  (fifo1_empty),
        .fifo1_rd_en  (fifo1_rd_en)
    );


    //=========================================================================
    // ASYNC FIFO-2
    //
    // FAST CLOCK DOMAIN -> SLOW CLOCK DOMAIN
    //
    // Payload:
    //
    //     { wen, ren, address, write_data }
    //
    // Width = 1 + 1 + 14 + 32 = 48 bits
    //=========================================================================

    async_fifo #(
        .WIDTH (FIFO2_WIDTH),
        .DEPTH      (FIFO_DEPTH)
    ) u_fifo2_fast_to_slow (

        // Fast domain - write side
        .wclk    (CLK_Fast),
        .wrst_n  (fast_rst_n),

        .w_data (fifo2_w_data),
        .wrt_en    (fifo2_wrt_en),
        .full    (fifo2_full),

        // Slow domain - read side
        .rclk    (CLK_Slow),
        .rrst_n  (slow_rst_n),

        .r_data (fifo2_r_data),
        .rd_en     (fifo2_rd_en),
        .empty    (fifo2_empty)
    );


    //=========================================================================
    // CACHE-DATA MEMORY CONTROL
    //
    // SLOW CLOCK DOMAIN
    //
    // FIFO-2
    //   |
    //   v
    // cache_dm_control
    //   |
    //   v
    // data_mem
    //   |
    //   v
    // FIFO-1
    //
    // IMPORTANT:
    // No TIMEOUT_CYCLES.
    // No timeout_error port.
    //=========================================================================

    cache_dm_control #(
        .DATA_WIDTH     (DATA_WIDTH),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .WORDS_PER_LINE (WORDS_PER_LINE)
    ) u_cache_dm_control (

        .clk   (CLK_Slow),
        .rst_n (slow_rst_n),

        // FIFO-2 -> Controller
        .fifo2_r_data (fifo2_r_data),
        .fifo2_empty  (fifo2_empty),
        .fifo2_rd_en  (fifo2_rd_en),

        // Controller -> Data Memory
        .dm_addr  (dm_addr),
        .dm_wdata (dm_wdata),
        .dm_wen   (dm_wen),
        .dm_ren   (dm_ren),

        // Data Memory -> Controller
        .dm_addr_echo  (dm_addr_echo),
        .dm_rdata      (dm_rdata),
        .dm_data_valid (dm_data_valid),

        // Controller -> FIFO-1
        .fifo1_w_data (fifo1_w_data),
        .fifo1_wrt_en (fifo1_wrt_en),
        .fifo1_full   (fifo1_full)
    );


    //=========================================================================
    // DATA MEMORY
    //
    // 16384 x 32
    //
    // IMPORTANT:
    // Your actual data_mem.v does NOT have a data_to_cpu port.
    //
    // Therefore the only outputs connected here are:
    //
    //     addr_to_sram
    //     data_to_sram
    //     data_valid
    //=========================================================================

    data_mem #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_data_mem (
        .clk   (CLK_Slow),
        .rst_n (slow_rst_n),

        // Controller -> Data Memory
        .addr_from_cpu (dm_addr),
        .data_from_cpu (dm_wdata),
        .wen           (dm_wen),
        .ren           (dm_ren),

        // Data Memory -> Controller
        .addr_to_sram (dm_addr_echo),
        .data_to_sram (dm_rdata),
        .data_valid   (dm_data_valid)
    );


    //=========================================================================
    // ASYNC FIFO-1
    //
    // SLOW CLOCK DOMAIN -> FAST CLOCK DOMAIN
    //
    // Payload:
    //
    //     { address, read_data }
    //
    // Width = 14 + 32 = 46 bits
    //=========================================================================

    async_fifo #(
        .WIDTH (FIFO1_WIDTH),
	//.DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (FIFO_DEPTH)
    ) u_fifo1_slow_to_fast (

        // Slow domain - write side
        .wclk    (CLK_Slow),
        .wrst_n  (slow_rst_n),

        .w_data (fifo1_w_data),
        .wrt_en    (fifo1_wrt_en),
        .full    (fifo1_full),

        // Fast domain - read side
        .rclk    (CLK_Fast),
        .rrst_n  (fast_rst_n),

        .r_data (fifo1_r_data),
        .rd_en     (fifo1_rd_en),
        .empty    (fifo1_empty)
    );


    //=========================================================================
    // DEBUG
    //=========================================================================

    //assign pc_debug = cpu_pc;


endmodule
