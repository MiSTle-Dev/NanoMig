// Copyright 2006, 2007 Dennis van Weeren
//
// This file is part of Minimig
//
// Minimig is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// Minimig is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//
//
// This is the bitplane part of denise
// It accepts data from the bus and converts it to serial video data (6 bits).
// It supports all ocs modes and also handles the pf1<->pf2 priority handling in
// a seperate module.


module denise_bitplanes
(
  input   clk,             // system bus clock
  input   clk7_en,
  input   reset,
  input   c1,            // 35ns clock enable signals (for synchronization with clk)
  input   c3,
  input   aga,
  input   [8:1] reg_address_in,   // register address
  input   [15:0] data_in,       // bus data in
  input   [48-1:0] chip48,  // big chipram read
  input   hires,             // high resolution mode select
  input   shres,             // super high resolution mode select
  input  [8:0] hpos,        // horizontal position (70ns resolution)
  input   strhor,
  input   bitplane_dma,
  input   bitplane_fetch_phase,
  input   bitplane_fetch_phase_valid,
  input   bitplane_fetch_unit_start,
  input   blank,
  input   hdiw,
  input   [3:0] planes,
  output   [8:1] bpldata,     // bitplane data out
  output         pixel_tick  // aligned unique-pixel event from plane 1
);


//register names and adresses
parameter BPLCON1 = 9'h102;
parameter BPL1DAT = 9'h110;
parameter BPL2DAT = 9'h112;
parameter BPL3DAT = 9'h114;
parameter BPL4DAT = 9'h116;
parameter BPL5DAT = 9'h118;
parameter BPL6DAT = 9'h11a;
parameter BPL7DAT = 9'h11c;
parameter BPL8DAT = 9'h11e;
parameter FMODE   = 9'h1fc;

//local signals
reg   [15:0] bplcon1;    // bplcon1 register
reg   [15:0] fmode;     // fmod reg
reg    [63:0] bpl1dat;    // buffer register for bit plane 2
reg    [63:0] bpl2dat;    // buffer register for bit plane 2
reg    [63:0] bpl3dat;    // buffer register for bit plane 3
reg    [63:0] bpl4dat;    // buffer register for bit plane 4
reg    [63:0] bpl5dat;    // buffer register for bit plane 5
reg    [63:0] bpl6dat;    // buffer register for bit plane 6
reg    [63:0] bpl7dat;    // buffer register for bit plane 5
reg    [63:0] bpl8dat;    // buffer register for bit plane 6
reg    load;        // bpl1dat written => load shif registers

reg    [7:0] extra_delay_f0;  // extra delay when not alligned ddfstart
reg    [7:0] extra_delay_f12;
reg    [7:0] extra_delay_f3;
reg    [7:0] extra_delay_r;
reg    [7:0] pf1h;      // playfield 1 horizontal scroll
reg    [7:0] pf2h;      // playfield 2 horizontal scroll
reg    [7:0] pf1h_del;    // delayed playfield 1 horizontal scroll
reg    [7:0] pf2h_del;    // delayed playfield 2 horizontal scroll

//--------------------------------------------------------------------------------------

// horizontal scroll depends on horizontal position when BPL0DAT in written
// visible display scroll is updated on fetch boundaries
// increasing scroll value during active display inserts blank pixels

always @(hpos)
  case (hpos[3:2])
    2'b00 : extra_delay_f0 = 8'b00_0000_00;
    2'b01 : extra_delay_f0 = 8'b00_1100_00;
    2'b10 : extra_delay_f0 = 8'b00_1000_00;
    2'b11 : extra_delay_f0 = 8'b00_0100_00;
  endcase

always @(hpos) extra_delay_f12 = {1'b0, 3'd0 - hpos[4:2], 4'b0000};

always @(hpos) extra_delay_f3 = {4'd0 - hpos[5:2], 4'b0000};

always @ (posedge clk) begin
  if (clk7_en) begin
    if (load) extra_delay_r <= #1 (fmode[1:0] == 2'b00) ? extra_delay_f0 : (fmode[1:0] == 2'b11) ? extra_delay_f3 : extra_delay_f12;
  end
end

//playfield 1 effective horizontal scroll
always @(posedge clk)
  if (clk7_en) begin
    if (!aga && (reg_address_in[8:1] == BPLCON1[8:1]))
      pf1h <= {2'b11,data_in[3:0],2'b11};
    else if (load)
      pf1h <= {bplcon1[11:10],bplcon1[3:0],bplcon1[9:8]};
  end

always @(posedge clk)
  if (clk7_en) begin
    pf1h_del <= pf1h + extra_delay_r;
  end

//playfield 2 effective horizontal scroll
always @(posedge clk)
  if (clk7_en) begin
    if (!aga && (reg_address_in[8:1] == BPLCON1[8:1]))
      pf2h <= {2'b11,data_in[7:4],2'b11};
    else if (load)
      pf2h <= {bplcon1[15:14],bplcon1[7:4],bplcon1[13:12]};
  end

always @(posedge clk)
  if (clk7_en) begin
    pf2h_del <= pf2h + extra_delay_r;
  end

//writing bplcon1 register : horizontal scroll codes for even and odd bitplanes
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      bplcon1 <= #1 16'h3300;
    if ((reg_address_in[8:1] == BPLCON1[8:1]))
      bplcon1 <= #1 aga ? data_in[15:0] : {2'b00,2'b11,2'b00,2'b11,data_in[7:0]};
  end

// fmode
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset)
      fmode <= #1 16'h0000;
    else if (aga && (reg_address_in[8:1] == FMODE[8:1]))
      fmode <= #1 data_in;
  end
end

reg [47:0] chip48_fmode=0;
always @ (*) begin
  case (fmode[1:0])
    2'b11   : chip48_fmode[47:0] = chip48[47:0];
    2'b10,
    2'b01   : chip48_fmode[47:0] = {chip48[47:32], 32'h00000000};
    default : chip48_fmode[47:0] = 48'h000000000000;
  endcase
end


//--------------------------------------------------------------------------------------

wire clk7n_en = c1 & c3;

reg [15:0] data16;
always @(posedge clk) if (clk7_en) data16 <= data_in;

//bitplane buffer register for plane 1
always @(posedge clk) begin
	reg st;
	if(clk7_en && reg_address_in[8:1] == BPL1DAT[8:1]) st <= 1;
	if(st & clk7n_en) begin
		st <= 0;
		bpl1dat <= {data16,chip48_fmode};
	end
end

//bitplane buffer register for plane 2
always @(posedge clk) begin
	reg st;
	if(clk7_en && reg_address_in[8:1] == BPL2DAT[8:1]) st <= 1;
	if(st & clk7n_en) begin
		st <= 0;
		bpl2dat <= {data16,chip48_fmode};
	end
end

//bitplane buffer register for plane 3
always @(posedge clk) begin
	reg st;
	if(clk7_en && reg_address_in[8:1] == BPL3DAT[8:1]) st <= 1;
	if(st & clk7n_en) begin
		st <= 0;
		bpl3dat <= {data16,chip48_fmode};
	end
end

//bitplane buffer register for plane 4
always @(posedge clk) begin
	reg st;
	if(clk7_en && reg_address_in[8:1] == BPL4DAT[8:1]) st <= 1;
	if(st & clk7n_en) begin
		st <= 0;
		bpl4dat <= {data16,chip48_fmode};
	end
end

//bitplane buffer register for plane 5
always @(posedge clk) begin
	reg st;
	if(clk7_en && reg_address_in[8:1] == BPL5DAT[8:1]) st <= 1;
	if(st & clk7n_en) begin
		st <= 0;
		bpl5dat <= {data16,chip48_fmode};
	end
end

//bitplane buffer register for plane 6
always @(posedge clk) begin
	reg st;
	if(clk7_en && reg_address_in[8:1] == BPL6DAT[8:1]) st <= 1;
	if(st & clk7n_en) begin
		st <= 0;
		bpl6dat <= {data16,chip48_fmode};
	end
end

//bitplane buffer register for plane 7
always @(posedge clk) begin
	reg st;
	if(clk7_en && reg_address_in[8:1] == BPL7DAT[8:1]) st <= 1;
	if(st & clk7n_en) begin
		st <= 0;
		bpl7dat <= {data16,chip48_fmode};
	end
end

//bitplane buffer register for plane 8
always @(posedge clk) begin
	reg st;
	if(clk7_en && reg_address_in[8:1] == BPL8DAT[8:1]) st <= 1;
	if(st & clk7n_en) begin
		st <= 0;
		bpl8dat <= {data16,chip48_fmode};
	end
end

//generate load signal when plane 1 is written
always @(posedge clk) if (clk7_en) load <= reg_address_in[8:1] == BPL1DAT[8:1];

wire ocs_lores_fmode0 = !aga && !hires && !shres && (fmode[1:0] == 2'b00);
wire ocs_bplcon1_write = clk7_en && (reg_address_in[8:1] == BPLCON1[8:1]);
wire [7:0] ocs_bplcon1_effective = ocs_bplcon1_write ? data_in[7:0] : bplcon1[7:0];
wire [3:0] ocs_phase_pf1 = ocs_bplcon1_effective[3:0];
wire [3:0] ocs_phase_pf2 = ocs_bplcon1_effective[7:4];


reg [8:0] ocs_hcmp;
wire [3:0] ocs_hphase = (strhor && clk7_en) ? 4'd2 : ocs_hcmp[3:0];
wire bpl1dat_now = ocs_lores_fmode0 && clk7_en &&
                   (reg_address_in[8:1] == BPL1DAT[8:1]);
wire bpl4dat_now = ocs_lores_fmode0 && clk7_en && bitplane_dma &&
                   (reg_address_in[8:1] == BPL4DAT[8:1]);
wire bpl5dat_now = ocs_lores_fmode0 && clk7_en && bitplane_dma &&
                   (reg_address_in[8:1] == BPL5DAT[8:1]);
wire bpl6dat_now = ocs_lores_fmode0 && clk7_en && bitplane_dma &&
                   (reg_address_in[8:1] == BPL6DAT[8:1]);
wire ocs_snapshot_event = ocs_lores_fmode0 && clk7_en && load;

reg [15:0] ocs_pending [1:6];
reg [15:0] ocs_active [1:6];
reg [3:0]  ocs_pipe [1:6];
reg ocs_pending_pf1, ocs_pending_pf2;
reg ocs_trigger;
reg ocs_trigger_delay;
reg seen_bpl1dat_this_line;


localparam [1:0] OCS_OWN_IDLE         = 2'd0;
localparam [1:0] OCS_OWN_INITIAL      = 2'd1;
localparam [1:0] OCS_OWN_DELAY_WAIT   = 2'd2;
localparam [1:0] OCS_OWN_DELAY_ACTIVE = 2'd3;
reg [1:0] ocs_ownership_state;
reg [1:0] ocs_delayed_fetch_stage;
reg [1:0] ocs_third_done;
reg ocs_first_saw_bpl4;
reg ocs_first_saw_bpl5;
reg ocs_first_saw_bpl6;
integer ocs_i;

function [15:0] ocs_holding_word;
  input [2:0] idx;
  begin
    case (idx)
      3'd1: ocs_holding_word = bpl1dat[63:48];
      3'd2: ocs_holding_word = bpl2dat[63:48];
      3'd3: ocs_holding_word = bpl3dat[63:48];
      3'd4: ocs_holding_word = bpl4dat[63:48];
      3'd5: ocs_holding_word = bpl5dat[63:48];
      default: ocs_holding_word = bpl6dat[63:48];
    endcase
  end
endfunction

wire ocs_same_phase = (ocs_phase_pf1 == ocs_phase_pf2);

wire ocs_match_pf1  = (ocs_hphase == ocs_phase_pf1);
wire ocs_match_pf2  = (ocs_hphase == ocs_phase_pf2);
wire first_bpl1dat_of_line = bpl1dat_now && !seen_bpl1dat_this_line;

always @(posedge clk) begin
  if (reset) begin
    ocs_hcmp <= 9'd2;
    for (ocs_i=1; ocs_i<=6; ocs_i=ocs_i+1) begin
      ocs_pending[ocs_i] <= 0;
      ocs_active[ocs_i] <= 0;
      ocs_pipe[ocs_i] <= 0;
    end
    ocs_pending_pf1 <= 0;
    ocs_pending_pf2 <= 0;
    ocs_trigger <= 0;
    ocs_trigger_delay <= 0;
    seen_bpl1dat_this_line <= 0;
  end else if (ocs_lores_fmode0) begin
    for (ocs_i=1; ocs_i<=6; ocs_i=ocs_i+1)
      ocs_pipe[ocs_i] <= {ocs_pipe[ocs_i][2:0],ocs_active[ocs_i][15]};

    if (blank) begin
      ocs_trigger <= 0;
      ocs_trigger_delay <= 0;
    end

    if (clk7_en) begin
      ocs_hcmp <= strhor ? 9'd2 : ocs_hcmp + 9'd1;

      if (strhor) begin
        ocs_trigger <= 0;
        ocs_trigger_delay <= 0;
        seen_bpl1dat_this_line <= 0;
      end

      if (ocs_trigger_delay) begin
        ocs_trigger <= 1;
        ocs_trigger_delay <= 0;
      end

      if (bpl1dat_now) begin
        if (!seen_bpl1dat_this_line) begin
          seen_bpl1dat_this_line <= 1;
          if (!hdiw)
            ocs_trigger <= 1;
          else
            ocs_trigger_delay <= 1;
        end
      end

      if (ocs_snapshot_event) begin
        for (ocs_i=1; ocs_i<=6; ocs_i=ocs_i+1)
          ocs_pending[ocs_i] <= ocs_holding_word(ocs_i[2:0]);
        ocs_pending_pf1 <= 1;
        ocs_pending_pf2 <= 1;
      end

      for (ocs_i=1; ocs_i<=6; ocs_i=ocs_i+1)
        ocs_active[ocs_i] <= {ocs_active[ocs_i][14:0],1'b0};

      if (ocs_same_phase) begin
        if (ocs_match_pf1 && (ocs_snapshot_event || ocs_pending_pf1)) begin
          for (ocs_i=1; ocs_i<=6; ocs_i=ocs_i+1)
            if (planes >= ocs_i[3:0])
              ocs_active[ocs_i] <= ocs_snapshot_event ? ocs_holding_word(ocs_i[2:0]) : ocs_pending[ocs_i];
          ocs_pending_pf1 <= 0;
          ocs_pending_pf2 <= 0;
        end
      end else begin
        if (ocs_match_pf1 && (ocs_snapshot_event || ocs_pending_pf1)) begin
          for (ocs_i=1; ocs_i<=5; ocs_i=ocs_i+2)
            if (planes >= ocs_i[3:0])
              ocs_active[ocs_i] <= ocs_snapshot_event ? ocs_holding_word(ocs_i[2:0]) : ocs_pending[ocs_i];
          ocs_pending_pf1 <= 0;
        end
        if (ocs_match_pf2 && (ocs_snapshot_event || ocs_pending_pf2)) begin
          for (ocs_i=2; ocs_i<=6; ocs_i=ocs_i+2)
            if (planes >= ocs_i[3:0])
              ocs_active[ocs_i] <= ocs_snapshot_event ? ocs_holding_word(ocs_i[2:0]) : ocs_pending[ocs_i];
          ocs_pending_pf2 <= 0;
        end
      end
    end
  end else begin
    ocs_pending_pf1 <= 0;
    ocs_pending_pf2 <= 0;
    ocs_trigger <= 0;
    ocs_trigger_delay <= 0;
    seen_bpl1dat_this_line <= 0;
    for (ocs_i=1; ocs_i<=6; ocs_i=ocs_i+1)
      ocs_pipe[ocs_i] <= 0;
  end
end



wire ocs_immediate_ownership_now = first_bpl1dat_of_line && (extra_delay_f0 == 8'h30);
wire ocs_first_dma_exact4 = ocs_first_saw_bpl4 &&
                            !ocs_first_saw_bpl5 && !ocs_first_saw_bpl6;
wire ocs_delayed_ownership_now = (extra_delay_f0 == 8'h10) && hdiw &&
                                 ocs_first_dma_exact4 && bitplane_fetch_phase_valid &&
                                 !bitplane_fetch_phase;
wire ocs_third_pf1_event = ocs_match_pf1 && (ocs_snapshot_event || ocs_pending_pf1);
wire ocs_third_pf2_event = ocs_match_pf2 && (ocs_snapshot_event || ocs_pending_pf2);
wire [1:0] ocs_third_done_now = ocs_third_done |
                                {ocs_third_pf2_event, ocs_third_pf1_event};

always @(posedge clk) begin
  if (reset || !ocs_lores_fmode0 || blank) begin
    ocs_ownership_state <= OCS_OWN_IDLE;
    ocs_delayed_fetch_stage <= 2'd0;
    ocs_third_done <= 2'b00;
    ocs_first_saw_bpl4 <= 1'b0;
    ocs_first_saw_bpl5 <= 1'b0;
    ocs_first_saw_bpl6 <= 1'b0;
  end else if (clk7_en) begin
    if (strhor) begin
      ocs_ownership_state <= OCS_OWN_IDLE;
      ocs_delayed_fetch_stage <= 2'd0;
      ocs_third_done <= 2'b00;
      ocs_first_saw_bpl4 <= 1'b0;
      ocs_first_saw_bpl5 <= 1'b0;
      ocs_first_saw_bpl6 <= 1'b0;
    end else begin
      if (!seen_bpl1dat_this_line) begin
        if (bitplane_fetch_unit_start) begin
          ocs_first_saw_bpl4 <= 1'b0;
          ocs_first_saw_bpl5 <= 1'b0;
          ocs_first_saw_bpl6 <= 1'b0;
        end
        if (bpl4dat_now) ocs_first_saw_bpl4 <= 1'b1;
        if (bpl5dat_now) ocs_first_saw_bpl5 <= 1'b1;
        if (bpl6dat_now) ocs_first_saw_bpl6 <= 1'b1;
      end

      if (ocs_ownership_state == OCS_OWN_DELAY_WAIT)
        ocs_ownership_state <= OCS_OWN_DELAY_ACTIVE;

      if (bpl1dat_now) begin
        if (!seen_bpl1dat_this_line) begin
          if (extra_delay_f0 == 8'h30)
            ocs_ownership_state <= OCS_OWN_INITIAL;
          else if (ocs_delayed_ownership_now)
            ocs_ownership_state <= OCS_OWN_DELAY_WAIT;
          else
            ocs_ownership_state <= OCS_OWN_IDLE;
          ocs_delayed_fetch_stage <= 2'd0;
          ocs_third_done <= 2'b00;
        end else if (ocs_ownership_state == OCS_OWN_INITIAL) begin
          ocs_ownership_state <= OCS_OWN_IDLE;
        end else if ((ocs_ownership_state == OCS_OWN_DELAY_WAIT) ||
                     (ocs_ownership_state == OCS_OWN_DELAY_ACTIVE)) begin
          if (ocs_delayed_fetch_stage == 2'd0)
            ocs_delayed_fetch_stage <= 2'd1;
          else if (ocs_delayed_fetch_stage == 2'd1) begin
            ocs_delayed_fetch_stage <= 2'd2;
            ocs_third_done <= 2'b00;
          end
        end
      end

      if (((ocs_ownership_state == OCS_OWN_DELAY_WAIT) ||
           (ocs_ownership_state == OCS_OWN_DELAY_ACTIVE)) &&
          (ocs_delayed_fetch_stage == 2'd2)) begin
        if (ocs_same_phase) begin
          if (ocs_third_pf1_event) begin
            ocs_ownership_state <= OCS_OWN_IDLE;
            ocs_delayed_fetch_stage <= 2'd0;
            ocs_third_done <= 2'b00;
          end
        end else begin
          ocs_third_done <= ocs_third_done_now;
          if (ocs_third_done_now == 2'b11) begin
            ocs_ownership_state <= OCS_OWN_IDLE;
            ocs_delayed_fetch_stage <= 2'd0;
            ocs_third_done <= 2'b00;
          end
        end
      end
    end
  end
end

wire [8:1] legacy_bpldata;
wire [8:1] ocs_raw = {2'b00,
                       ocs_pipe[6][3],ocs_pipe[5][3],ocs_pipe[4][3],
                       ocs_pipe[3][3],ocs_pipe[2][3],ocs_pipe[1][3]};
wire [8:1] ocs_bpldata = ocs_trigger ? ocs_raw : 8'b0;

wire use_ocs_pending_stream = ocs_lores_fmode0 &&
                              (ocs_immediate_ownership_now ||
                               (ocs_ownership_state == OCS_OWN_INITIAL) ||
                               (ocs_ownership_state == OCS_OWN_DELAY_ACTIVE));

//--------------------------------------------------------------------------------------

//instantiate bitplane 1 parallel to serial converters, this plane is loaded directly from bus
denise_bitplane_shifter bplshft1
(
  .clk(clk),
  .clk7_en(clk7_en),
  .c1(c1),
  .c3(c3),
  .load(load),
  .hires(hires),
  .shres(shres),
  .fmode(fmode[1:0]),
  .aga(aga),
  .data_in(bpl1dat),
  .scroll(pf1h_del),
  .out(legacy_bpldata[1]),
  .pixel_tick(pixel_tick)
);

//instantiate bitplane 2 to 6 parallel to serial converters, (loaded from buffer registers)
denise_bitplane_shifter bplshft2
(
  .clk(clk),
  .clk7_en(clk7_en),
  .c1(c1),
  .c3(c3),
  .load(load),
  .hires(hires),
  .shres(shres),
  .fmode(fmode[1:0]),
  .aga(aga),
  .data_in(bpl2dat),
  .scroll(pf2h_del),
  .out(legacy_bpldata[2])
);

denise_bitplane_shifter bplshft3
(
  .clk(clk),
  .clk7_en(clk7_en),
  .c1(c1),
  .c3(c3),
  .load(load),
  .hires(hires),
  .shres(shres),
  .fmode(fmode[1:0]),
  .aga(aga),
  .data_in(bpl3dat),
  .scroll(pf1h_del),
  .out(legacy_bpldata[3])
);

denise_bitplane_shifter bplshft4
(
  .clk(clk),
  .clk7_en(clk7_en),
  .c1(c1),
  .c3(c3),
  .load(load),
  .hires(hires),
  .shres(shres),
  .fmode(fmode[1:0]),
  .aga(aga),
  .data_in(bpl4dat),
  .scroll(pf2h_del),
  .out(legacy_bpldata[4])
);

denise_bitplane_shifter bplshft5
(
  .clk(clk),
  .clk7_en(clk7_en),
  .c1(c1),
  .c3(c3),
  .load(load),
  .hires(hires),
  .shres(shres),
  .fmode(fmode[1:0]),
  .aga(aga),
  .data_in(bpl5dat),
  .scroll(pf1h_del),
  .out(legacy_bpldata[5])
);

denise_bitplane_shifter bplshft6
(
  .clk(clk),
  .clk7_en(clk7_en),
  .c1(c1),
  .c3(c3),
  .load(load),
  .hires(hires),
  .shres(shres),
  .fmode(fmode[1:0]),
  .aga(aga),
  .data_in(bpl6dat),
  .scroll(pf2h_del),
  .out(legacy_bpldata[6])
);

denise_bitplane_shifter bplshft7
(
  .clk(clk),
  .clk7_en(clk7_en),
  .c1(c1),
  .c3(c3),
  .load(load),
  .hires(hires),
  .shres(shres),
  .fmode(fmode[1:0]),
  .aga(aga),
  .data_in(bpl7dat),
  .scroll(pf1h_del),
  .out(legacy_bpldata[7])
);

denise_bitplane_shifter bplshft8
(
  .clk(clk),
  .clk7_en(clk7_en),
  .c1(c1),
  .c3(c3),
  .load(load),
  .hires(hires),
  .shres(shres),
  .fmode(fmode[1:0]),
  .aga(aga),
  .data_in(bpl8dat),
  .scroll(pf2h_del),
  .out(legacy_bpldata[8])
);


assign bpldata = use_ocs_pending_stream ? ocs_bpldata : legacy_bpldata;

endmodule

