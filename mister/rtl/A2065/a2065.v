/*
 * a2065.v — Commodore A2065 ZorroII Ethernet card.
 *
 * Everything the card needs on the FPGA side lives in here: the LANCE chip
 * registers, the boardram window, and the mailbox that carries both to the
 * host over DDR3. The rest of the core sees only the 68k bus, an interrupt,
 * and one memory port.
 *
 * The host half — the Am7990 controller itself, the descriptor rings and the
 * network socket — runs on the HPS, in Main under support/minimig/.
 *
 *   68k side (clk_sys)          this module                host (via DDR3)
 *   ------------------          ----------                 ---------------
 *   $EAxxxx chip regs   ---->   a2065_regfile     ---->     CMD ring
 *                               (CSR reads answered from a shadow the host
 *                                keeps current, so reads never stall)
 *   $EA8000 boardram    <-->    a2065_ddram       <-->      flat DDR3 window
 *                               (DTACK stretched for the DDR3 round trip)
 *   INT2                <----   a2065_ddr3_mailbox <----    interrupt state
 *
 * Register writes are posted to a ring and the bus released as soon as the
 * entry lands, so the Amiga never waits on host scheduling. Only the boardram
 * path stretches DTACK, and only for FPGA-side work.
 */

module a2065 (
    // ── 68k bus, Amiga clock domain ──────────────────────────────────────
    input  wire        clk_sys,
    input  wire        rst_n_sys,

    input  wire [23:1] cpu_addr,
    input  wire [15:0] cpu_data_in,
    output wire [15:0] cpu_data_out,   // zero unless this card is addressed
    input  wire        cpu_rw,         // 1 = read
    input  wire        cpu_as_n,
    input  wire        cpu_uds_n,
    input  wire        cpu_lds_n,
    input  wire        sel,            // $EAxxxx decode from gary
    output wire        nrdy,           // stretch DTACK
    output wire        int2,           // to Paula, already synchronised here

    input  wire [7:0]  card_base,      // autoconfig base address
    input  wire        card_configured,

    // ── DDR3, memory clock domain ────────────────────────────────────────
    input  wire        clk_ddr,
    output wire [28:0] mem_address,
    output wire [7:0]  mem_burstcount,
    output wire        mem_read,
    input  wire [63:0] mem_readdata,
    input  wire        mem_readdatavalid,
    output wire [63:0] mem_writedata,
    output wire [7:0]  mem_byteenable,
    output wire        mem_write,
    input  wire        mem_waitrequest
);

    // ── chip registers ↔ mailbox ─────────────────────────────────────────
    wire        cmd_pending, cmd_clear;
    wire [6:0]  cmd_rap;
    wire [15:0] cmd_data;
    wire [15:0] csr0, csr1, csr2, csr3;

    // ── boardram window ↔ mailbox ────────────────────────────────────────
    wire        bram_req_valid, bram_req_rw, bram_req_ack, bram_resp_valid;
    wire [13:0] bram_req_addr;
    wire [15:0] bram_req_wdata, bram_resp_data;
    wire [1:0]  bram_req_be;

    wire [15:0] regs_dout, bram_dout;
    wire        regs_nrdy, bram_nrdy;

    // Both halves drive zero unless addressed, so the card presents a single
    // value to the core's read mux.
    assign cpu_data_out = regs_dout | bram_dout;
    assign nrdy         = regs_nrdy | bram_nrdy;

    a2065_regfile regfile (
        .clk            (clk_sys),
        .rst_n          (rst_n_sys),
        .cpu_addr       ({cpu_addr, 1'b0}),
        .cpu_rw         (cpu_rw),
        .cpu_as_n       (cpu_as_n),
        .cpu_ds_n       (cpu_uds_n & cpu_lds_n),
        .cpu_data_in    (cpu_data_in),
        .cpu_data_out   (regs_dout),
        .regs_nrdy      (regs_nrdy),
        .card_base      (card_base),
        .card_configured(card_configured),
        .cmd_pending    (cmd_pending),
        .cmd_rap        (cmd_rap),
        .cmd_data       (cmd_data),
        .cmd_clear      (cmd_clear),
        .csr0_in        (csr0),
        .csr1_in        (csr1),
        .csr2_in        (csr2),
        .csr3_in        (csr3)
    );

    a2065_ddram boardram (
        .clk_sys              (clk_sys),
        .rst_n_sys            (rst_n_sys),
        .cpu_addr             (cpu_addr),
        .cpu_data_in          (cpu_data_in),
        .cpu_data_out         (bram_dout),
        .cpu_rw               (cpu_rw),
        .cpu_as_n             (cpu_as_n),
        .cpu_uds_n            (cpu_uds_n),
        .cpu_lds_n            (cpu_lds_n),
        .sel                  (sel),
        .nrdy                 (bram_nrdy),
        .bram_req_valid       (bram_req_valid),
        .bram_req_addr        (bram_req_addr),
        .bram_req_wdata       (bram_req_wdata),
        .bram_req_rw          (bram_req_rw),
        .bram_req_be          (bram_req_be),
        .bram_req_ack_audio   (bram_req_ack),
        .bram_resp_valid_audio(bram_resp_valid),
        .bram_resp_data_audio (bram_resp_data)
    );

    wire int2_ddr;

    a2065_ddr3_mailbox mailbox (
        .clk              (clk_ddr),
        .rst_n            (rst_n_sys),

        .cmd_pending      (cmd_pending),
        .cmd_rap          (cmd_rap),
        .cmd_data         (cmd_data),
        .cmd_clear        (cmd_clear),

        .csr0_out         (csr0),
        .csr1_out         (csr1),
        .csr2_out         (csr2),
        .csr3_out         (csr3),
        .a2065_int2       (int2_ddr),

        .bram_req_valid   (bram_req_valid),
        .bram_req_addr    (bram_req_addr),
        .bram_req_wdata   (bram_req_wdata),
        .bram_req_rw      (bram_req_rw),
        .bram_req_be      (bram_req_be),
        .bram_req_ack     (bram_req_ack),
        .bram_resp_valid  (bram_resp_valid),
        .bram_resp_data   (bram_resp_data),

        .avl_address      (mem_address),
        .avl_burstcount   (mem_burstcount),
        .avl_read         (mem_read),
        .avl_readdata     (mem_readdata),
        .avl_readdatavalid(mem_readdatavalid),
        .avl_writedata    (mem_writedata),
        .avl_byteenable   (mem_byteenable),
        .avl_write        (mem_write),
        .avl_waitrequest  (mem_waitrequest)
    );

    // The interrupt is raised in the memory clock domain and consumed in the
    // Amiga's, so synchronise it here rather than leaving that to the caller.
    reg int2_s1, int2_s2;
    always @(posedge clk_sys) begin
        int2_s1 <= int2_ddr;
        int2_s2 <= int2_s1;
    end
    assign int2 = int2_s2;

endmodule
