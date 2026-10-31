//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
//                                                                          //
// DDR3 memory interface                                                    // 
// Copyright (c)2019 Alexey Melnikov                                        //
// Based on SDRAM controller by Tobias Gubener                              //
//                                                                          //
// This source file is free software: you can redistribute it and/or modify //
// it under the terms of the GNU General Public License as published        //
// by the Free Software Foundation, either version 3 of the License, or     //
// (at your option) any later version.                                      //
//                                                                          //
// This source file is distributed in the hope that it will be useful,      //
// but WITHOUT ANY WARRANTY; without even the implied warranty of           //
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            //
// GNU General Public License for more details.                             //
//                                                                          //
// You should have received a copy of the GNU General Public License        //
// along with this program.  If not, see <http://www.gnu.org/licenses/>.    //
//                                                                          //
//////////////////////////////////////////////////////////////////////////////

module ddram_ctrl
(
	// system
	input             sysclk,
	input             reset_n,
	input             cache_rst,
	input             cache_inhibit,
	input       [3:0] cpu_cache_ctrl,
	input             dcache_sw_en,

	// DDR3    
	output            DDRAM_CLK,
	input             DDRAM_BUSY,
	output      [7:0] DDRAM_BURSTCNT,
	output     [28:0] DDRAM_ADDR,
	input      [63:0] DDRAM_DOUT,
	input             DDRAM_DOUT_READY,
	output            DDRAM_RD,
	output     [63:0] DDRAM_DIN,
	output      [7:0] DDRAM_BE,
	output            DDRAM_WE,

	// Second memory port, shared onto the same DDR3 interface. Used by the
	// A2065 Ethernet card, which touches DDR3 rarely; the CPU's fast RAM has
	// priority over it and is never made to wait.
	input      [28:0] mem2_address,
	input       [7:0] mem2_burstcount,
	input             mem2_read,
	output     [63:0] mem2_readdata,
	output            mem2_readdatavalid,
	input      [63:0] mem2_writedata,
	input       [7:0] mem2_byteenable,
	input             mem2_write,
	output            mem2_waitrequest,

	// cpu
	input      [28:1] cpuAddr,
	input             cpuCS,
	input       [1:0] cpustate,
	input             cpuL,
	input             cpuU,
	input      [15:0] cpuWR,
	output     [15:0] cpuRD,
	input             ramshared,
	input             cpuLong,
	output            ramready,
	input             cpuLong1,
	input      [15:0] cpuWR_lo,
	output     [15:0] cpuRD_hi,
	output            ramready_l,

	input      [28:1] dmaAddr,
	input             dmaCS,
	input             dmaWE,
	input             dmaL,
	input             dmaU,
	input      [15:0] dmaWR,
	output reg [15:0] dmaRD,
	output            dmaACK
);

wire ramsel = cpuCS & (~&cpustate | ~cpuU | ~cpuL);

wire cache_hit;
wire cache_hit_l;
reg  w_l1;
wire cache_req;
reg  cache_fill;
wire cache_ack;
wire cache_idle;
reg        dma_snoop_act;
reg [28:1] dma_snoop_adr;
reg [15:0] dma_snoop_dat;
reg  [1:0] dma_snoop_bs;
wire        kept_ok;
wire [63:0] kept_dat;
wire        kept_take;

cpu_cache_new
#(.LINE_TAKE(1), .SPLIT_READ(1))
cpu_cache
(
	.clk              (sysclk),                 // clock
	.rst              (~reset_n | ~cache_rst),  // cache reset
	.cpu_cache_ctrl   (cpu_cache_ctrl),         // CPU cache control
	.dcache_sw_en     (dcache_sw_en),
	.cache_inhibit    (cache_inhibit | ramshared), // cache inhibit
	.cpu_cs           (ramsel),                 // cpu activity
	.cpu_adr          (cpuAddr),                // cpu address
	.cpu_bs           (~{cpuU, cpuL}),          // cpu byte selects
	.cpu_we           (cpustate == 3),          // cpu write
	.cpu_ir           (cpustate == 0),          // cpu instruction read
	.cpu_dr           (cpustate == 2),          // cpu data read
	.cpu_dat_w        (cpuWR),                  // cpu write data
	.cpu_dat_r        (cpuRD),                  // cpu read data
	.cpu_ack          (cache_hit),              // cpu acknowledge
	.wb_en            (cache_ack),              // write enable
	.cpu_idle         (cache_idle),
	.sdr_dat_r        (ddr_swap ? {ddr_data[7:0], ddr_data[15:8]} : ddr_data), // sdram read data
	.sdr_read_req     (cache_req),              // sdram read request from cache
	.sdr_read_ack     (cache_fill),             // sdram read acknowledge to cache
	.snoop_act        (dma_snoop_act),
	.snoop_adr        (dma_snoop_adr),
	.snoop_dat_w      (dma_snoop_dat),
	.snoop_bs         (dma_snoop_bs),
	.buf_ok           (kept_ok),
	.buf_dat          (kept_dat),
	.buf_take         (kept_take),
	.cpu_long         (cpuLong1 & ~ramshared),
	.cpu_dat_w_lo     (cpuWR_lo),
	.cpu_dat_hi       (cpuRD_hi),
	.cpu_ack_l        (cache_hit_l)
);

// write buffer, enables CPU to continue while a write is in progress
localparam WQN = 4;
reg  [28:2] wq_a  [0:WQN-1];
reg  [15:0] wq_dh [0:WQN-1];
reg  [15:0] wq_dl [0:WQN-1];
reg   [1:0] wq_bh [0:WQN-1];
reg   [1:0] wq_bl [0:WQN-1];
reg [WQN-1:0] wq_vm;
reg   [2:0] wq_n;
reg   [1:0] wq_h, wq_t;
reg         stg_v;
reg  [28:2] stg_a;
reg  [15:0] stg_d;
reg   [1:0] stg_b;
reg        write_ena;
wire        wq_pop;

wire [15:0] w_dat  = ramshared ? {cpuWR[7:0],cpuWR[15:8]} : cpuWR;
wire  [1:0] w_be   = ramshared ? ~{cpuL, cpuU} : ~{cpuU, cpuL};
wire        w_new  = ramsel && (cpustate == 3) && (cache_ack | cache_idle) && ~write_ena;
wire        w_room = (wq_n != WQN);
wire        w_lo   = stg_v && (cpuAddr[28:2] == stg_a) && cpuAddr[1];
wire        w_hi   = ~stg_v && cpuLong && ~cpuAddr[1] && ~ramshared;
wire        w_l1n  = ~stg_v && cpuLong1 && ~cpuAddr[1] && ~ramshared;
wire        stg_fl = stg_v && ramsel && ~write_ena && ~((cpustate == 3) && (cpuAddr[28:2] == stg_a) && cpuAddr[1]);

wire [28:2] wh_a  = wq_a[wq_h];
wire [15:0] wh_dh = wq_dh[wq_h];
wire [15:0] wh_dl = wq_dl[wq_h];
wire  [1:0] wh_bh = wq_bh[wq_h];
wire  [1:0] wh_bl = wq_bl[wq_h];

reg wq_line;
integer qi;
always @* begin
	wq_line = stg_v && (stg_a[28:3] == cpuAddr[28:3]);
	for (qi = 0; qi < WQN; qi = qi + 1)
		if (wq_vm[qi] && (wq_a[qi][28:3] == cpuAddr[28:3])) wq_line = 1'b1;
end

integer qj;
always @ (posedge sysclk) begin
	reg        push;
	reg [28:2] pa;
	reg [15:0] pdh, pdl;
	reg  [1:0] pbh, pbl;

	push = 0;
	pa = 0; pdh = 0; pdl = 0; pbh = 0; pbl = 0;
	if(~reset_n) begin
		wq_n      <= 0;
		wq_h      <= 0;
		wq_t      <= 0;
		wq_vm     <= 0;
		stg_v     <= 0;
		write_ena   <= 0;
		w_l1      <= 0;
	end else begin
		if(stg_fl) begin
			if(w_room) begin
				push = 1; pa = stg_a; pdh = stg_d; pbh = stg_b;
				stg_v <= 0;
			end
		end
		else if(w_new) begin
			if(w_lo) begin
				if(w_room) begin
					push = 1; pa = stg_a; pdh = stg_d; pbh = stg_b; pdl = w_dat; pbl = w_be;
					stg_v     <= 0;
					write_ena <= 1;
				end
			end
			else if(w_l1n) begin
				if(w_room) begin
					push = 1; pa = cpuAddr[28:2]; pdh = w_dat; pbh = w_be; pdl = cpuWR_lo; pbl = 2'b11;
					write_ena <= 1;
					w_l1      <= 1;
				end
			end
			else if(w_hi) begin
				stg_v     <= 1;
				stg_a     <= cpuAddr[28:2];
				stg_d     <= w_dat;
				stg_b     <= w_be;
				write_ena <= 1;
			end
			else if(~stg_v & w_room) begin
				push = 1; pa = cpuAddr[28:2];
				if(cpuAddr[1]) begin pdl = w_dat; pbl = w_be; end
				else           begin pdh = w_dat; pbh = w_be; end
				write_ena <= 1;
			end
		end

		// wq_t names an invalid scratch slot whenever w_room is true.
		// Capture its address without the CPU-address-derived push enable.
		// A staged flush/low-half push always uses stg_a; other pushes use cpuAddr.
		// Valid entries and all queue commit/ack timing remain unchanged.
		if(w_room) wq_a[wq_t] <= stg_v ? stg_a : cpuAddr[28:2];
		// Capture only the invalid tail scratch slot. Every committed upper
		// half and byte mask has the same value as the original push logic.
		// No address comparison is needed on the upper data/mask enable.
		if(w_room) begin
			wq_dh[wq_t] <= stg_v ? stg_d : (cpuAddr[1] ? 16'b0 : w_dat);
			wq_bh[wq_t] <= stg_v ? stg_b : (cpuAddr[1] ? 2'b0 : w_be);
		end
		if(push) begin
			wq_dl[wq_t] <= pdl;
			wq_bl[wq_t] <= pbl;
			wq_t        <= (wq_t == WQN - 1) ? 2'd0 : wq_t + 1'd1;
		end
		// The SDRAM controller has picked up the request
		if(wq_pop) wq_h <= (wq_h == WQN - 1) ? 2'd0 : wq_h + 1'd1;
		wq_n  <= wq_n + {2'd0, push} - {2'd0, wq_pop};
		for(qj = 0; qj < WQN; qj = qj + 1) begin
			if(push   && (wq_t == qj)) wq_vm[qj] <= 1'b1;
			if(wq_pop && (wq_h == qj)) wq_vm[qj] <= 1'b0;
		end
		if(~ramsel) write_ena <= 0;
		if(~ramsel) w_l1 <= 0;
	end
end

wire wq_any = (wq_n != 0) | stg_v;

assign ramready = cache_hit || write_ena;
assign ramready_l = cache_hit_l || (write_ena && w_l1);

reg dmaCS_sync1;
reg dmaCS_sync2;
reg dmaCS_sync3;
always @ (posedge sysclk) begin
	if (~reset_n) begin
		dmaCS_sync1 <= 0;
		dmaCS_sync2 <= 0;
		dmaCS_sync3 <= 0;
	end else begin
		dmaCS_sync1 <= dmaCS;
		dmaCS_sync2 <= dmaCS_sync1;
		dmaCS_sync3 <= dmaCS_sync2;
	end
end
wire dmaCS_rise = dmaCS_sync2 & ~dmaCS_sync3;

reg        dma_write_req;
reg        dma_write_ack;
reg [28:1] dmaWriteAddr;
reg [15:0] dmaWriteDat;
reg  [1:0] dmaWriteBE;
reg        dmaACK_r;

reg        dma_read_req;
reg        dma_read_ack;
reg [28:1] dmaReadAddr;
reg  [1:0] dmaReadBA;
reg        dma_read_in_flight;
reg        dma_after_wr;

wire       wr_first = dma_after_wr & wq_any;

assign dmaACK = dmaACK_r;

always @ (posedge sysclk) begin
	dma_snoop_act <= 0;

	if (~reset_n) begin
		dma_write_req <= 0;
		dma_read_req  <= 0;
		dmaACK_r      <= 0;
		dma_after_wr  <= 0;
	end else begin
		if (~wq_any) dma_after_wr <= 0;

		if (dmaCS_rise & ~dma_write_req & ~dma_read_req & ~dmaACK_r) begin
			dma_after_wr <= wq_any;
			if (dmaWE) begin
			dmaWriteAddr  <= dmaAddr;
			dmaWriteDat   <= dmaWR;
			dmaWriteBE    <= ~{dmaU, dmaL};
			dma_write_req <= 1'b1;
			dma_snoop_act <= 1'b1;
			dma_snoop_adr <= dmaAddr;
			dma_snoop_dat <= dmaWR;
			dma_snoop_bs  <= ~{dmaU, dmaL};
			end else begin
				dmaReadAddr  <= dmaAddr;
				dma_read_req <= 1'b1;
			end
		end

		if (dma_write_ack) begin
			dma_write_req <= 1'b0;
			dmaACK_r      <= 1'b1;
		end

		if (dma_read_ack) begin
			dma_read_req <= 1'b0;
			dmaACK_r     <= 1'b1;
		end

		if (~dmaCS_sync2) dmaACK_r <= 1'b0;
	end
end

assign DDRAM_CLK = sysclk;

// Fast RAM's own view of DDR3. It goes through the arbiter below rather than
// straight to the pins, so that the second port can share the interface.
reg  [28:0] ram_addr;
reg  [63:0] ram_din;
reg   [7:0] ram_be;
reg   [7:0] ram_bcnt = 8'd1;
reg         ram_rd, ram_we;
wire        ram_busy;
wire [63:0] ram_dout       = DDRAM_DOUT;
wire        ram_dout_ready;

wire [28:0] hs_address;
wire  [7:0] hs_burstcount;
wire        hs_read, hs_write, hs_waitrequest;
wire [63:0] hs_writedata;
wire  [7:0] hs_byteenable;

reg         q2_v = 0;
reg  [28:0] q2_address;
reg   [7:0] q2_burstcount;
reg         q2_read, q2_write;
reg  [63:0] q2_writedata;
reg   [7:0] q2_byteenable;
wire        q2_wait;
assign      mem2_waitrequest = q2_v;

always @(posedge sysclk) begin
	if(~reset_n) q2_v <= 0;
	else if(q2_v) q2_v <= q2_wait;
	else if(mem2_read | mem2_write) begin
		q2_v          <= 1;
		q2_address    <= mem2_address;
		q2_burstcount <= mem2_burstcount;
		q2_read       <= mem2_read;
		q2_write      <= mem2_write;
		q2_writedata  <= mem2_writedata;
		q2_byteenable <= mem2_byteenable;
	end
end

a2065_ddram_arbiter arbiter
(
	.clk             (sysclk),
	.rst             (~reset_n),

	.m0_address      (ram_addr),
	.m0_burstcount   (ram_bcnt),
	.m0_read         (ram_rd),
	.m0_readdata     (),
	.m0_readdatavalid(ram_dout_ready),
	.m0_writedata    (ram_din),
	.m0_byteenable   (ram_be),
	.m0_write        (ram_we),
	.m0_waitrequest  (ram_busy),

	.m1_address      (q2_address),
	.m1_burstcount   (q2_burstcount),
	.m1_read         (q2_v & q2_read),
	.m1_readdata     (),
	.m1_readdatavalid(mem2_readdatavalid),
	.m1_writedata    (q2_writedata),
	.m1_byteenable   (q2_byteenable),
	.m1_write        (q2_v & q2_write),
	.m1_waitrequest  (q2_wait),

	.s_address       (hs_address),
	.s_burstcount    (hs_burstcount),
	.s_read          (hs_read),
	.s_readdata      (DDRAM_DOUT),
	.s_readdatavalid (DDRAM_DOUT_READY),
	.s_writedata     (hs_writedata),
	.s_byteenable    (hs_byteenable),
	.s_write         (hs_write),
	.s_waitrequest   (hs_waitrequest)
);

ddram_hold hold
(
	.clk           (sysclk),
	.rst           (~reset_n),
	.u_address     (hs_address),
	.u_burstcount  (hs_burstcount),
	.u_read        (hs_read),
	.u_writedata   (hs_writedata),
	.u_byteenable  (hs_byteenable),
	.u_write       (hs_write),
	.u_waitrequest (hs_waitrequest),
	.d_address     (DDRAM_ADDR),
	.d_burstcount  (DDRAM_BURSTCNT),
	.d_read        (DDRAM_RD),
	.d_writedata   (DDRAM_DIN),
	.d_byteenable  (DDRAM_BE),
	.d_write       (DDRAM_WE),
	.d_waitrequest (DDRAM_BUSY)
);

assign mem2_readdata = DDRAM_DOUT;

reg        ddr_swap;
reg [15:0] ddr_data;

reg  [2:0] state = 0;
reg  [1:0] ba;
reg [63:0] dout;

reg        wq_line_r;
reg        sb_on_cpu;
reg [28:3] cpu_up, cpu_dn;
reg        cpu_below_sb;
reg [28:3] cpu_up2, cpu_dn2;

reg        sb_v;
reg [28:3] sb_a;
reg [63:0] sb_d;
reg        sb_wait;
reg        sb_kill;
reg        sc_v, sc_wait, sc_kill;
reg [28:3] sc_a;
reg [63:0] sc_d;
wire       sb_hit = sb_v && sb_on_cpu && ~ramshared;
wire       sb_free = ~sb_v & ~sb_wait;
wire       sc_free = ~sc_v & ~sc_wait;
reg        sb_up;
reg [28:3] sb_last;
reg        dn_first;
assign     kept_dat = sb_d;
assign     kept_ok  = sb_v && (sb_a == cpuAddr[28:3]) && ~ramshared && ~wq_line && ~dma_write_req && ramsel &&
                     (cpustate == 2);
reg        strm_on;
reg [28:3] nx_a;
reg [28:3] nx_a1;
wire [28:3] nx_a_nx;
wire [28:3] nx_a1_nx;
assign     nx_a_nx  = sb_up ? nx_a + 1'd1 : nx_a - 1'd1;
assign     nx_a1_nx = sb_up ? nx_a1 + 1'd1 : nx_a1 - 1'd1;
wire       m2_req  = q2_v;
function in_buf(input [28:3] a);
	in_buf = ((sb_v | sb_wait) && (sb_a == a)) || ((sc_v | sc_wait) && (sc_a == a));
endfunction

wire       st0     = (state == 3'd0);
wire       dw_sel  = st0 & ~dma_write_ack & dma_write_req & ~wr_first;
wire       dr_sel  = st0 & ~dw_sel & ~dma_read_ack & dma_read_req & ~dma_read_in_flight & ~wr_first;
wire       next_sel = st0 & ~dw_sel & ~dr_sel & ~cache_req & strm_on & ~sc_wait & ~sc_v & ~m2_req;
wire       rd_1st  = cache_req & ~wq_line_r;
wire       rd_sel0 = st0 & ~dw_sel & ~dr_sel & rd_1st;
wire       wq_sel  = st0 & ~dw_sel & ~dr_sel & ~rd_sel0 & ~next_sel & (wq_n != 0);
wire       rd_sel  = rd_sel0;
assign     wq_pop  = wq_sel & ~ram_busy;
wire [28:3] ra_cpu  = (~ramshared && cpu_below_sb) ? cpu_dn : cpuAddr[28:3];
wire [28:3] ra_next = wq_sel ? wh_a[28:3] : dw_sel ? dmaWriteAddr[28:3] : dr_sel ? dmaReadAddr[28:3] :
                      (rd_sel & ~sb_hit) ? ra_cpu : nx_a;

always @(posedge sysclk) begin
	wq_line_r     <= wq_line;
	sb_on_cpu     <= (sb_a == cpuAddr[28:3]);
	cpu_up        <= cpuAddr[28:3] + 1'd1;
	cpu_dn        <= cpuAddr[28:3] - 1'd1;
	cpu_below_sb  <= (cpuAddr[28:3] == sb_last - 1'd1);
	cpu_up2       <= cpuAddr[28:3] + 2'd2;
	cpu_dn2       <= cpuAddr[28:3] - 2'd2;
end

always @ (posedge sysclk) begin
	reg        e_take;
	reg        e_miss;
	reg        e_reset;
	reg        e_rs_w;
	reg [28:3] e_rs_a;
	reg        e_issue;
	reg        e_drop;
	reg        n0_v, n0_w, n0_k, n1_v, n1_w, n1_k;
	reg [28:3] n0_a, n1_a;
	reg [63:0] n0_d, n1_d;

	e_take  = kept_take & sb_v;
	e_miss  = 0;
	e_reset = 0;
	e_rs_w  = 0;
	e_rs_a  = 0;
	e_issue = 0;
	e_drop  = 0;

	cache_fill <= 0;
	ddr_data <= dout[{ba, 4'b0000} +:16];

	if(~ram_busy) begin
		ram_we  <= 0;
		ram_rd  <= 0;
	end
	if(~(ram_rd | ram_we) | ~ram_busy) ram_addr <= {3'b001, ra_next};

	if(~reset_n) begin
		state         <= 0;
		dma_write_ack <= 0;
		dma_read_ack       <= 0;
		dma_read_in_flight <= 0;
		ram_bcnt      <= 8'd1;
		sb_v          <= 0;
		sb_wait       <= 0;
		sb_kill       <= 0;
		sc_v          <= 0;
		sc_wait       <= 0;
		sc_kill       <= 0;
		sb_up         <= 1;
		sb_last       <= 0;
		dn_first      <= 0;
		strm_on       <= 0;
	end
	else begin
		if(kept_take) begin
			sb_last <= sb_a;
			if(sb_v) strm_on <= 1;
		end
		case(state)
			0: begin
					if(dw_sel) begin
						if(~ram_busy) begin
							ram_be        <= {6'b000000,dmaWriteBE}<<{dmaWriteAddr[2:1],1'b0};
							ram_din       <= {dmaWriteDat,dmaWriteDat,dmaWriteDat,dmaWriteDat};
							ram_bcnt      <= 8'd1;
							ram_we        <= 1;
							dma_write_ack <= 1;
							e_drop         = in_buf(dmaWriteAddr[28:3]);
						end
					end
					if(dr_sel) begin
						if(~ram_busy & ~sb_wait & ~sc_wait) begin
							ram_be             <= 8'hFF;
							ram_bcnt           <= 8'd1;
							ram_rd             <= 1;
							dmaReadBA          <= dmaReadAddr[2:1];
							dma_read_in_flight <= 1;
							state              <= 1;
						end
					end
					if(next_sel) begin
						if(~ram_busy) begin
							ram_be   <= 8'hFF;
							ram_bcnt <= 8'd1;
							ram_rd   <= 1;
							e_issue   = 1;
						end
					end
					if(wq_sel) begin
						if(~ram_busy) begin
							ram_be   <= {4'b0000, wh_bl, wh_bh} << {wh_a[2], 2'b00};
							ram_din  <= {wh_dl, wh_dh, wh_dl, wh_dh};
							ram_bcnt <= 8'd1;
							ram_we   <= 1;
							e_drop    = in_buf(wh_a[28:3]);
						end
					end
					if(rd_sel) begin
						if(sb_hit) begin
							ddr_data   <= sb_d[{cpuAddr[2:1], 4'b0000} +:16];
							dout       <= sb_d;
							ba         <= cpuAddr[2:1] + 1'd1;
							cache_fill <= 1;
							ddr_swap   <= 0;
							e_take      = 1;
							strm_on    <= 1;
							if(~ram_busy && ~m2_req) begin
								ram_be   <= 8'hFF;
								ram_bcnt <= 8'd1;
								ram_rd   <= 1;
								e_issue   = 1;
							end
							sb_last    <= sb_a;
							state      <= 2;
						end
						else if(~sb_wait & ~sc_wait) begin
							e_miss    = 1;
							e_rs_a    = (~ramshared && cpu_below_sb) ? cpu_dn : cpu_up;
							strm_on  <= 0;
							if(~ram_busy) begin
								ram_be   <= 8'hFF;
								e_reset   = 1;
								if(~ramshared && cpu_below_sb) begin
									ram_bcnt <= 8'd2;
									dn_first <= 1;
									e_rs_w    = 1;
									sb_up    <= 0;
									nx_a     <= cpu_dn2;
								end
								else begin
									ram_bcnt <= ramshared ? 8'd1 : 8'd2;
									e_rs_w    = ~ramshared;
									sb_up    <= 1;
									nx_a     <= cpu_up2;
								end
								sb_last  <= cpuAddr[28:3];
								ram_rd   <= 1;
								ba         <= cpuAddr[2:1];
								state      <= 1;
								ddr_swap   <= ramshared;
							end
						end
					end
				end
			1: if(ram_dout_ready) begin
					if (dma_read_in_flight) begin
						dmaRD              <= ram_dout[{dmaReadBA, 4'b0000} +:16];
						dma_read_ack       <= 1;
						dma_read_in_flight <= 0;
						state              <= 0;
					end else if (dn_first) begin
						dn_first <= 0;
					end else begin
					ddr_data      <= ram_dout[{ba, 4'b0000} +:16];
					dout          <= ram_dout;
					cache_fill    <= 1;
					ba            <= ba + 1'd1;
					state         <= state + 1'd1;
				end
				end
			2,3: begin
					cache_fill    <= 1;
					ba            <= ba + 1'd1;
					state         <= state + 1'd1;
				end
			4: begin
					cache_fill    <= 1;
					state         <= 0;
				end
		endcase

		if(~dma_write_req) dma_write_ack <= 0;
		if(~dma_read_req)  dma_read_ack  <= 0;

		n0_v = sb_v; n0_w = sb_wait; n0_k = sb_kill; n0_a = sb_a; n0_d = sb_d;
		n1_v = sc_v; n1_w = sc_wait; n1_k = sc_kill; n1_a = sc_a; n1_d = sc_d;
		if(ram_dout_ready && ((state != 3'd1) || dn_first)) begin
			if(n0_w) begin
				n0_d = ram_dout; n0_v = ~n0_k; n0_w = 0; n0_k = 0;
			end
			else if(n1_w) begin
				n1_d = ram_dout; n1_v = ~n1_k; n1_w = 0; n1_k = 0;
			end
		end
		if(e_take) begin
			n0_v = n1_v; n0_w = n1_w; n0_k = n1_k; n0_d = n1_d;
			n1_v = 0; n1_w = 0; n1_k = 0;
		end
		if(e_miss) begin
			n0_v = 0; n0_w = e_reset & e_rs_w; n0_k = 0;
			n1_v = 0; n1_w = 0; n1_k = 0;
		end
		if(e_issue) begin
			if(e_take ? sc_free : sb_free) begin
				n0_w = 1; n0_k = 0;
			end
			else begin
				n1_w = 1; n1_k = 0;
			end
		end
		n0_a = e_miss ? e_rs_a : e_take ? (sc_free ? nx_a : sc_a) : (sb_free ? nx_a : sb_a);
		n1_a = (e_take | sc_free) ? nx_a : sc_a;
		if(e_drop) begin
			n0_v = 0; n0_k = n0_w;
			n1_v = 0; n1_k = n1_w;
			strm_on <= 0;
		end
		sb_v <= n0_v; sb_wait <= n0_w; sb_kill <= n0_k; sb_a <= n0_a; sb_d <= n0_d;
		sc_v <= n1_v; sc_wait <= n1_w; sc_kill <= n1_k; sc_a <= n1_a; sc_d <= n1_d;
		if(e_issue) begin
			nx_a  <= nx_a1;
			nx_a1 <= nx_a1_nx;
		end
		else nx_a1 <= nx_a_nx;
	end
end

endmodule

module ddram_hold
(
	input             clk,
	input             rst,
	input      [28:0] u_address,
	input       [7:0] u_burstcount,
	input             u_read,
	input      [63:0] u_writedata,
	input       [7:0] u_byteenable,
	input             u_write,
	output            u_waitrequest,
	output     [28:0] d_address,
	output      [7:0] d_burstcount,
	output            d_read,
	output     [63:0] d_writedata,
	output      [7:0] d_byteenable,
	output            d_write,
	input             d_waitrequest
);

reg        h_v = 0;
reg [28:0] h_address;
reg  [7:0] h_burstcount;
reg        h_read, h_write;
reg [63:0] h_writedata;
reg  [7:0] h_byteenable;

assign u_waitrequest = h_v;
assign d_address     = h_v ? h_address    : u_address;
assign d_burstcount  = h_v ? h_burstcount : u_burstcount;
assign d_read        = h_v ? h_read       : u_read;
assign d_writedata   = h_v ? h_writedata  : u_writedata;
assign d_byteenable  = h_v ? h_byteenable : u_byteenable;
assign d_write       = h_v ? h_write      : u_write;

always @(posedge clk) begin
	if(~h_v) begin
		h_address    <= u_address;
		h_burstcount <= u_burstcount;
		h_read       <= u_read;
		h_writedata  <= u_writedata;
		h_byteenable <= u_byteenable;
		h_write      <= u_write;
	end
	if(rst) h_v <= 0;
	else if(h_v) h_v <= d_waitrequest;
	else h_v <= (u_read | u_write) & d_waitrequest;
end

endmodule
