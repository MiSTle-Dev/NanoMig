/*
 * a2065_regfile.v
 *
 * Am7990 LANCE register file + CSR doorbell.
 *
 * Replaces the DTACK-stretch bridge RPC (a2065_registers.v bridge mode).
 * The 68k reads/writes RAP/RDP at full bus speed.  RDP writes raise a
 * doorbell for the ARM daemon; the ARM writes status bits back into the
 * CSR shadow which the 68k polls at full speed.
 *
 * No DTACK stretch on any access.  RDP writes always complete immediately;
 * if the previous doorbell is still pending, the new write overwrites it
 * (the ARM daemon only needs the latest register state).
 */

module a2065_regfile (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [23:0] cpu_addr,
    input  wire        cpu_rw,
    input  wire        cpu_as_n,
    input  wire        cpu_ds_n,
    input  wire [15:0] cpu_data_in,
    output wire [15:0] cpu_data_out,
    output wire        regs_nrdy,

    input  wire [7:0]  card_base,
    input  wire        card_configured,

    output reg         cmd_pending,
    output reg  [6:0]  cmd_rap,
    output reg  [15:0] cmd_data,
    input  wire        cmd_clear,

    input  wire [15:0] csr0_in,
    input  wire [15:0] csr1_in,
    input  wire [15:0] csr2_in,
    input  wire [15:0] csr3_in
);

    wire sel_chipreg = card_configured &&
                       (cpu_addr[23:16] == card_base) &&
                       (cpu_addr[15:2]  == 14'h1000) &&
                       (!cpu_as_n) &&
                       (!cpu_ds_n);

    wire is_rap = cpu_addr[1];

    reg [6:0]  rap;
    reg [15:0] csr_shadow [0:3];

    always @(posedge clk) begin
        csr_shadow[0] <= csr0_in;
        csr_shadow[1] <= csr1_in;
        csr_shadow[2] <= csr2_in;
        csr_shadow[3] <= csr3_in;
    end

    reg [15:0] chip_id_out;
    always @(*) begin
        chip_id_out = 16'h0000;
        case (rap)
        7'd88: chip_id_out = 16'h0001;
        7'd89: chip_id_out = 16'h3003;
        default: begin
            if (rap < 4)
                chip_id_out = csr_shadow[rap];
        end
        endcase
    end

    assign cpu_data_out = (sel_chipreg && cpu_rw) ?
                          (is_rap ? {9'b0, rap} : chip_id_out) : 16'h0000;

    reg cmd_clear_s, cmd_clear_s1;
    always @(posedge clk) begin
        cmd_clear_s  <= cmd_clear;
        cmd_clear_s1 <= cmd_clear_s;
    end

    // RDP writes back-pressure (stretch DTACK) until the doorbell is fully
    // drained by the ARM daemon (cmd_clear arrives only after the mailbox
    // sees the daemon clear the DDR3 CMD slot).  This serializes the rapid
    // RAP/RDP register sequence used by LANCE INIT so no write is lost.
    // RAP writes stay local and immediate; reads are unaffected (zero latency).
    localparam W_IDLE = 2'd0, W_WAIT = 2'd1, W_DONE = 2'd2;
    reg [1:0] wstate;
    reg [15:0] wd_cnt;

    wire rdp_wr = sel_chipreg && !cpu_rw && !is_rap;
    wire rap_wr = sel_chipreg && !cpu_rw &&  is_rap;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rap         <= 7'd0;
            cmd_pending <= 1'b0;
            cmd_rap     <= 7'd0;
            cmd_data    <= 16'd0;
            wstate      <= W_IDLE;
            wd_cnt      <= 16'd0;
        end else begin
            if (rap_wr)
                rap <= cpu_data_in[6:0];

            case (wstate)
            W_IDLE: begin
                if (rdp_wr) begin
                    cmd_rap     <= rap;
                    cmd_data    <= cpu_data_in;
                    cmd_pending <= 1'b1;
                    wstate      <= W_WAIT;
                    wd_cnt      <= 16'd0;
                end
            end
            W_WAIT: begin
                if (cmd_clear_s1 || &wd_cnt) begin
                    cmd_pending <= 1'b0;
                    wstate      <= W_DONE;
                end
                else
                    wd_cnt <= wd_cnt + 16'd1;
            end
            W_DONE: begin
                if (!rdp_wr)            // bus cycle ended (DS deasserted)
                    wstate <= W_IDLE;
            end
            default: wstate <= W_IDLE;
            endcase
        end
    end

    assign regs_nrdy = (wstate == W_WAIT);

endmodule
