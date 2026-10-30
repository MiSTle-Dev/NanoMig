//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
//                                                                          //
// Copyright (c) 2009/2011 Tobias Gubener                                   //
// Subdesign fAMpIGA by TobiFlex                                            //
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
//////////////////////////////////////////////////////////////////////////////
//
// Code re-work:
// - Shrink 16 to 12 cycles to work at quarter lower frequency with the same performance.
// - Support for 64MB SDRAM
//
// (C)2019 Alexey Melnikov
//


module sdram_ctrl
#(parameter FOLD_CHIP_ARBITRATION=0)
(
	// system
	input             sysclk,
	input             c_7m,
	input             reset_n,
	input             cache_rst,
	input             cache_inhibit,
	input       [3:0] cpu_cache_ctrl,
	input             dcache_sw_en,
	// sdram
	output reg [12:0] sd_addr,
	output reg  [1:0] sd_ba,
	output            sd_cs,
	output reg        sd_we,
	output reg        sd_ras,
	output reg        sd_cas,
	output reg  [1:0] sd_dqm,
	inout  reg [15:0] sd_data,
	output reg        sd_clk,
	output            sd_cke,
	// chip
	input      [24:1] chipAddr,
	input [24:1] raw_chip_addr, addon_chip_addr,
	input raw_chip_dma, raw_chip_rw, addon_chip_claim,
	input             chipL,
	input             chipU,
	input             chipRW,
	input             chipDMA,
	input      [15:0] chipWR,
	output reg [15:0] chipRD,
	output     [47:0] chip48,
	input             chip32,
	input      [15:0] chipWR2,
	output reg [15:0] chipRD2,
	// cpu
	input      [24:1] cpuAddr,
	input             cpuCS,
	input       [1:0] cpustate,
	input             cpuL,
	input             cpuU,
	input      [15:0] cpuWR,
	output     [15:0] cpuRD,
	output            ramready
);

assign sd_cs = 0;
assign sd_cke = 1;

//// parameters ////
localparam [2:0]
	IDLE = 0,
	CHIP = 1,
	CPU_READCACHE = 2,
	CPU_WRITECACHE = 3;


////////////////////////////////////////
// reset
////////////////////////////////////////

reg reset;
always @(posedge sysclk) begin
	reg [7:0] reset_cnt;

	if(!reset_n) begin
		reset_cnt     <= 0;
		reset         <= 0;
	end else begin
		if(reset_cnt == 170) begin
			if(sdram_phase[15]) reset <= 1;
		end
		else begin
			reset_cnt <= reset_cnt + 8'd1;
		end
	end
end

wire ramsel = cpuCS & (~&cpustate | ~cpuU | ~cpuL);

// cpu cache
wire cache_rd_ack;
wire cache_wr_ack;
wire cache_req;
reg        a_wr2 = 0;
reg        a_rd2 = 0;
reg [15:0] datawr2;
reg        chipWE2 = 0;
reg        snoop2 = 0;
cpu_cache_new cpu_cache
(
	.clk              (sysclk),                // clock
	.rst              (!reset || !cache_rst),  // cache reset
	.cpu_cache_ctrl   (cpu_cache_ctrl),        // CPU cache control
	.dcache_sw_en     (dcache_sw_en),
	.cache_inhibit    (cache_inhibit),         // cache inhibit
	.cpu_cs           (ramsel),                // cpu activity
	.cpu_adr          (cpuAddr),               // cpu address
	.cpu_bs           ({!cpuU, !cpuL}),        // cpu byte selects
	.cpu_we           (cpustate == 3),         // cpu write
	.cpu_ir           (cpustate == 0),         // cpu instruction read
	.cpu_dr           (cpustate == 2),         // cpu data read
	.cpu_dat_w        (cpuWR),                 // cpu write data
	.cpu_dat_r        (cpuRD),                 // cpu read data
	.cpu_ack          (cache_rd_ack),          // cpu acknowledge
	.wb_en            (cache_wr_ack),          // write enable
	.cpu_idle         (),
	.sdr_dat_r        (sdata_reg),             // sdram read data
	.sdr_read_req     (cache_req),             // sdram read request from cache
	.sdr_read_ack     (cache_fill),            // sdram read acknowledge to cache
	.snoop_act        (chipWE | chipWE2),      // snoop act (write only - just update existing data in cache)
	.snoop_adr        (snoop2 ? {chipAddr[24:2], 1'b1} : chipAddr), // snoop address
	.snoop_dat_w      (snoop2 ? chipWR2 : chipWR), // snoop write data
	.snoop_bs         (snoop2 ? 2'b11 : {!chipU, !chipL}), // snoop byte selects
	.buf_ok           (1'b0),
	.buf_dat          (64'd0),
	.buf_take         (),
	.cpu_long         (1'b0),
	.cpu_dat_w_lo     (16'd0),
	.cpu_dat_hi       (),
	.cpu_ack_l        ()
);

reg cache_fill;
always @ (posedge sysclk) begin
	cache_fill <= 0;

	if(init_done && slot_type == CPU_READCACHE) begin
		case(1'b1)
		   sdram_phase[7], sdram_phase[9], sdram_phase[11], sdram_phase[13]: cache_fill <= 1;
		endcase
	end
end

// write buffer, enables CPU to continue while a write is in progress
reg        write_ena;
reg        write_req;
reg        write_ack;
reg  [1:0] write_dqm;
reg [24:1] writeAddr;
reg [15:0] writeDat;
reg        fwd_en = 1'b0;
reg  [1:0] fwd_pos;
reg [15:0] fwd_dat;
reg  [1:0] fwd_dqm;

always @ (posedge sysclk) begin
	reg  [1:0] write_state;

	if(~reset_n) begin
		write_req   <= 0;
		write_ena   <= 0;
		write_state <= 0;
	end else begin
		case(write_state)
			default:
				if(~write_ena && ramsel && cpustate == 3) begin
					writeAddr <= cpuAddr;
					writeDat  <= cpuWR;
					write_dqm <= {cpuU, cpuL};
					write_req <= 1;
					if(cache_wr_ack) begin
						write_ena   <= 1;
						write_state <= 1;
					end
				end

			1: if(write_ack) begin
					write_req   <= 0;
					write_state <= 2;
				end

			2: if(!write_ack) begin
					write_state <= 0;
				end
		endcase

		if(~ramsel) write_ena <= 0;
	end
end

assign ramready = cache_rd_ack || write_ena;

//// chip line read ////
reg [15:0] chip48_1, chip48_2, chip48_3;

always @ (posedge sysclk) begin
	reg [15:0] sdata_chip;
	reg [15:0] m;

	sdata_chip <= sdata_reg;
	m = sdata_chip;
	if(fwd_en) begin
		if(!fwd_dqm[1]) m[15:8] = fwd_dat[15:8];
		if(!fwd_dqm[0]) m[7:0]  = fwd_dat[7:0];
	end
	if(slot_type == CHIP) begin
		case(1'b1)
			 sdram_phase[9]: chipRD   <= (fwd_en && fwd_pos==2'd0) ? m : sdata_chip;
			sdram_phase[11]: begin
					chip48_1 <= (fwd_en && fwd_pos==2'd1) ? m : sdata_chip;
					if(a_rd2) chipRD2 <= (fwd_en && fwd_pos==2'd1) ? m : sdata_chip;
				end
			sdram_phase[13]: chip48_2 <= (fwd_en && fwd_pos==2'd2) ? m : sdata_chip;
			sdram_phase[15]: chip48_3 <= (fwd_en && fwd_pos==2'd3) ? m : sdata_chip;
		endcase
	end
end

assign chip48 = {chip48_1, chip48_2, chip48_3};


////////////////////////////////////////
// SDRAM control
////////////////////////////////////////


//// init counter ////
reg [3:0] initstate;
reg       init_done;
always @ (posedge sysclk) begin
	if(!reset) begin
		initstate <= 0;
		init_done <= 0;
	end else begin
		if (sdram_phase[15]) begin
			if(~&initstate) initstate <= initstate + 1'd1;
			else init_done <= 1;
		end
	end
end


//// sdram state ////
reg [3:0] sdram_state;
(* preserve *) reg [15:0] sdram_phase;
always @ (posedge sysclk) begin
	reg old_7m;

	sdram_state <= sdram_state + 1'd1;
	sdram_phase <= 16'h0001 << (sdram_state + 4'd1);

	old_7m <= c_7m;
	if(~old_7m & c_7m) begin
		sdram_state <= 0;
		sdram_phase <= 16'h0001;
	end
end

//// sdram control ////

reg  [2:0] slot_type = IDLE;
reg [15:0] sdata_reg;
reg        chipWE;

wire [23:0] ras_address;
wire ras_address_write;
generate if(FOLD_CHIP_ARBITRATION) begin: ras_fold
 reg [3:0] pick;
 always @* begin
  pick=0;
  if(~raw_chip_dma | ~raw_chip_rw)pick[0]=1;
  else if(addon_chip_claim)pick[1]=1;
  else if(write_req)pick[2]=1;
  else if(cache_req)pick[3]=1;
 end
 assign ras_address = ({24{pick[0]}} & raw_chip_addr)
                    | ({24{pick[1]}} & addon_chip_addr)
                    | ({24{pick[2]}} & writeAddr)
                    | ({24{pick[3]}} & cpuAddr);
 assign ras_address_write = |pick;
end else begin: ras_legacy
reg [2:0] ras_address_pick;
always @* begin
 ras_address_pick=0;
 if(~chipDMA | ~chipRW)ras_address_pick[0]=1;
 else if(write_req)ras_address_pick[1]=1;
 else if(cache_req)ras_address_pick[2]=1;
end
assign ras_address =
 ({24{ras_address_pick[0]}} & chipAddr) |
 ({24{ras_address_pick[1]}} & writeAddr) |
 ({24{ras_address_pick[2]}} & cpuAddr);
assign ras_address_write = |ras_address_pick;
end endgenerate

always @ (posedge sysclk) begin
	reg        cas_sd_cas;
	reg        cas_sd_we;
	reg  [1:0] cas_dqm;
	reg [15:0] datawr;
	reg  [9:0] casaddr;
	// One-hot saturating refresh timer: bit15 is the original rcnt==15.
	reg [15:0] rcnt;
	
	sd_clk <= sdram_state[0];

	if(~sdram_state[0]) begin
		sd_ras                <= 1;
		sd_cas                <= 1;
		sd_we                 <= 1;
		sd_data               <= 16'hZZZZ;
		chipWE                <= 0;
	end

	if(sdram_phase[4]) begin
		chipWE2 <= a_wr2;
		snoop2  <= a_wr2;
	end
	if(sdram_phase[6]) chipWE2 <= 0;
	if(sdram_phase[8]) snoop2  <= 0;

	if(sdram_state[0]) sdata_reg <= sd_data;

	if(!init_done) begin
		slot_type             <= IDLE;
		casaddr               <= 0;
		rcnt                  <= 16'h0001;
		a_wr2                 <= 0;
		a_rd2                 <= 0;
		sd_dqm                <= 3;
		sd_ba                 <= 0;
		if(sdram_phase[0]) begin
			case(initstate)
				4 : begin // PRECHARGE
					sd_addr[10]  <= 1; // all banks
					sd_ras       <= 0;
					sd_cas       <= 1;
					sd_we        <= 0;
				end
				8,10 : begin // AUTOREFRESH
					sd_ras       <= 0;
					sd_cas       <= 0;
					sd_we        <= 1;
				end
				13 : begin // LOAD MODE REGISTER
					sd_ras       <= 0;
					sd_cas       <= 0;
					sd_we        <= 0;
					sd_addr      <= 13'b0001000100010; // CL=2, BURST=4
				end
			endcase
		end
	end else begin

		case(1'b1)

			// RAS
			sdram_phase[0]: begin
				// Shared command bits depend on request presence, not winner priority.
                // Keep address/data/ack arbitration and every cycle unchanged.
                cas_sd_cas <= chipDMA & chipRW & !write_req & !cache_req;
                sd_ras <= chipDMA & chipRW & !write_req & !cache_req & !rcnt[15];
                sd_cas <= !(chipDMA & chipRW & !write_req & !cache_req & rcnt[15]);
				cas_sd_we       <= 1;
				cas_dqm         <= 0;
				sd_dqm          <= 3;
				slot_type       <= IDLE;
				fwd_en          <= 0;
				a_wr2           <= 0;
				a_rd2           <= 0;

				if(!rcnt[15]) rcnt <= {rcnt[14:0],1'b0};

				if(ras_address_write) {sd_ba,sd_addr,casaddr[8:0]} <= ras_address;
				// we give the chipset first priority
				// (this includes anything on the "motherboard" - chip RAM, slow RAM and Kickstart, turbo modes notwithstanding)
				if(~chipDMA | ~chipRW) begin
					slot_type    <= CHIP;
					// Common RAS address capture below.
					
					cas_dqm      <= {chipU,chipL};
					
					cas_sd_we    <= chipRW;
					datawr       <= chipWR;
					chipWE       <= !chipRW;
					a_wr2        <= chip32 & !chipRW;
					a_rd2        <= chip32 &  chipRW;
					datawr2      <= chipWR2;
					if(chipRW & write_req & (writeAddr[24:3] == chipAddr[24:3])) begin
						fwd_en  <= 1'b1;
						fwd_pos <= writeAddr[2:1] - chipAddr[2:1];
						fwd_dat <= writeDat;
						fwd_dqm <= write_dqm;
					end
				end
				else if(write_req) begin
					slot_type    <= CPU_WRITECACHE;
					// Common RAS address capture below.
					
					cas_dqm      <= write_dqm;
					cas_sd_we    <= 0;
					
					write_ack    <= 1; // let the write buffer know we're about to write
					datawr       <= writeDat;
				end
				// request from read cache
				else if(cache_req) begin
					slot_type    <= CPU_READCACHE;
					// Common RAS address capture below.
					
					
				end
				else if(rcnt[15]) begin
					// REFRESH
					
					
					rcnt         <= 16'h0001;
				end
			end

			// CAS
			sdram_phase[2]: begin
				sd_addr         <= {~a_wr2, casaddr}; // AUTO PRECHARGE
				sd_cas          <= cas_sd_cas;
				sd_dqm          <= 0;
				if(!cas_sd_we) begin
					sd_data      <= datawr;
					sd_addr[12:11]<= cas_dqm;
					sd_dqm       <= cas_dqm;
					sd_we        <= 0;
				end
				write_ack       <= 0; // indicate to write that it's safe to accept the next write
			end

			sdram_phase[4]: if(a_wr2) begin
				sd_addr         <= {2'b00, 1'b1, casaddr[9:1], 1'b1};
				sd_dqm          <= 0;
				sd_data         <= datawr2;
				sd_cas          <= 0;
				sd_we           <= 0;
			end
		endcase
	end
end

endmodule
