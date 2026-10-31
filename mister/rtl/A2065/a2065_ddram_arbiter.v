/*
 * a2065_ddram_arbiter.v
 *
 * Two-master Avalon-MM arbiter for the core's DDR3 port (the emu DDRAM_*
 * interface).  Master 0 is the Minimig fast-RAM controller; master 1 is the
 * A2065 DDR3 mailbox.
 *
 * Fixed priority, master 0 wins.  m0 carries every 68k fast-RAM access, so it
 * must never be made to wait on the A2065: a stalled fast-RAM path hangs the
 * Amiga, while a stalled mailbox only delays a network register poll by a few
 * cycles.  m1 issues one single-beat transfer at a time and polls at a low
 * rate, so it takes the gaps between m0's bursts and loses nothing in practice.
 *
 * Arbitration is per burst, decided when a burst starts and held until it
 * completes, since Avalon gives no way to interleave two masters' beats on one
 * slave.  Reads and writes complete differently:
 *
 *   write burst  done after burstcount beats have been accepted (!waitrequest)
 *   read burst   done after burstcount beats have returned (readdatavalid)
 *
 * The single-beat case needs care: the start of a burst and its first accepted
 * beat happen in the same cycle, so that beat is counted at the point the
 * burst is granted rather than by the tracking block, which would otherwise
 * still see burst_active low and miss it.  Getting this wrong leaves the
 * arbiter latched to one master forever.
 */

module a2065_ddram_arbiter #(
    parameter ADDR_W  = 29,
    parameter DATA_W  = 64,
    parameter BURST_W = 8,
    parameter BYTE_W  = 8
)(
    input  wire                clk,
    input  wire                rst,

    // Master 0 — Minimig fast RAM (priority)
    input  wire [ADDR_W-1:0]   m0_address,
    input  wire [BURST_W-1:0]  m0_burstcount,
    input  wire                m0_read,
    output wire [DATA_W-1:0]   m0_readdata,
    output wire                m0_readdatavalid,
    input  wire [DATA_W-1:0]   m0_writedata,
    input  wire [BYTE_W-1:0]   m0_byteenable,
    input  wire                m0_write,
    output wire                m0_waitrequest,

    // Master 1 — A2065 mailbox
    input  wire [ADDR_W-1:0]   m1_address,
    input  wire [BURST_W-1:0]  m1_burstcount,
    input  wire                m1_read,
    output wire [DATA_W-1:0]   m1_readdata,
    output wire                m1_readdatavalid,
    input  wire [DATA_W-1:0]   m1_writedata,
    input  wire [BYTE_W-1:0]   m1_byteenable,
    input  wire                m1_write,
    output wire                m1_waitrequest,

    // Slave — DDR3
    output wire [ADDR_W-1:0]   s_address,
    output wire [BURST_W-1:0]  s_burstcount,
    output wire                s_read,
    input  wire [DATA_W-1:0]   s_readdata,
    input  wire                s_readdatavalid,
    output wire [DATA_W-1:0]   s_writedata,
    output wire [BYTE_W-1:0]   s_byteenable,
    output wire                s_write,
    input  wire                s_waitrequest
);

    localparam M0 = 1'b0;
    localparam M1 = 1'b1;

    reg               busy;          // a burst is in flight
    reg               owner;         // which master owns it
    reg               owner_is_read;
    reg [BURST_W:0]   beats_left;

    wire m0_req = m0_read | m0_write;
    wire m1_req = m1_read | m1_write;

    // While idle, m0 wins outright; m1 is granted only when m0 is quiet.
    wire       start_m0 = !busy && m0_req;
    wire       start_m1 = !busy && !m0_req && m1_req;
    wire       sel      = busy ? owner : (m0_req ? M0 : M1);
    (* keep *) wire sel_a  = busy ? owner : (m0_req ? M0 : M1);
    (* keep *) wire sel_d0 = busy ? owner : (m0_req ? M0 : M1);
    (* keep *) wire sel_d1 = busy ? owner : (m0_req ? M0 : M1);
    wire       starting = start_m0 | start_m1;

    wire [BURST_W-1:0] sel_burstcount = (sel == M0) ? m0_burstcount : m1_burstcount;
    wire               sel_read       = (sel == M0) ? m0_read       : m1_read;
    wire               sel_write      = (sel == M0) ? m0_write      : m1_write;

    // A beat is accepted whenever the slave takes a write, or a read command is
    // issued. Read data comes back later and is counted by readdatavalid.
    wire write_beat = sel_write && !s_waitrequest;
    wire beat_done  = owner_is_read ? s_readdatavalid : write_beat;
    wire [BURST_W:0] m0_more = (owner == M0 && owner_is_read && m0_read && !s_waitrequest)
                             ? {1'b0, m0_burstcount} : {(BURST_W+1){1'b0}};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy          <= 1'b0;
            owner         <= M0;
            owner_is_read <= 1'b0;
            beats_left    <= 0;
        end
        else if (!busy) begin
            if (starting && !s_waitrequest) begin
                owner         <= sel;
                owner_is_read <= sel_read;
                if (sel_read) begin
                    // The whole read burst is issued as one command; every
                    // beat is still outstanding until its data comes back.
                    busy       <= 1'b1;
                    beats_left <= sel_burstcount;
                end
                else begin
                    // The first write beat is placed in this same cycle, so
                    // only the remainder is outstanding.
                    busy       <= (sel_burstcount > 1);
                    beats_left <= sel_burstcount - 1'b1;
                end
            end
        end
        else begin
            beats_left <= beats_left + m0_more - beat_done;
            if (beats_left + m0_more - beat_done == 0) busy <= 1'b0;
        end
    end

    // Read data returns out of band. A burst of the other master cannot start
    // while beats are still to come back (busy), so remembering the owner of
    // the most recent burst is enough to route them.
    reg rd_owner;
    always @(posedge clk or posedge rst) begin
        if (rst) rd_owner <= M0;
        else if (!busy && starting && !s_waitrequest && sel_read) rd_owner <= sel;
    end

    assign s_address    = (sel_a == M0) ? m0_address    : m1_address;
    assign s_burstcount = (sel_a == M0) ? m0_burstcount : m1_burstcount;
    assign s_read       = (sel_a == M0) ? m0_read       : m1_read;
    assign s_writedata  = {(sel_d1 == M0) ? m0_writedata[DATA_W-1:DATA_W/2] : m1_writedata[DATA_W-1:DATA_W/2],
                           (sel_d0 == M0) ? m0_writedata[DATA_W/2-1:0]      : m1_writedata[DATA_W/2-1:0]};
    assign s_byteenable = {(sel_d1 == M0) ? m0_byteenable[BYTE_W-1:BYTE_W/2] : m1_byteenable[BYTE_W-1:BYTE_W/2],
                           (sel_d0 == M0) ? m0_byteenable[BYTE_W/2-1:0]      : m1_byteenable[BYTE_W/2-1:0]};
    assign s_write      = (sel_a == M0) ? m0_write      : m1_write;

    // Back-pressure. A master that is merely idle must see the slave's own
    // waitrequest, not a busy signal: ddram_ctrl only issues a request while
    // ~DDRAM_BUSY, so holding an idle master off would stop it ever asking,
    // which in turn would keep it held off — a deadlock that never lets the
    // 68k reach fast RAM. Only a master that genuinely cannot have the bus
    // right now is stalled.
    assign m0_waitrequest = (busy && owner == M1) ? 1'b1          // m1 mid-burst
                                                  : s_waitrequest;

    assign m1_waitrequest = (busy && owner == M1) ? s_waitrequest // m1 owns it
                          : (busy || m0_req)      ? 1'b1          // m0 owns or wants it
                                                  : s_waitrequest;

    assign m0_readdata       = s_readdata;
    assign m1_readdata       = s_readdata;
    assign m0_readdatavalid  = s_readdatavalid && (rd_owner == M0);
    assign m1_readdatavalid  = s_readdatavalid && (rd_owner == M1);

endmodule
