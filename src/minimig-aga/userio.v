////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Copyright 2006, 2007 Dennis van Weeren                                     //
//                                                                            //
// This file is part of Minimig                                               //
//                                                                            //
// Minimig is free software; you can redistribute it and/or modify            //
// it under the terms of the GNU General Public License as published by       //
// the Free Software Foundation; either version 3 of the License, or          //
// (at your option) any later version.                                        //
//                                                                            //
// Minimig is distributed in the hope that it will be useful,                 //
// but WITHOUT ANY WARRANTY; without even the implied warranty of             //
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              //
// GNU General Public License for more details.                               //
//                                                                            //
// You should have received a copy of the GNU General Public License          //
// along with this program.  If not, see <http://www.gnu.org/licenses/>.      //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// This is the user IO module                                                 //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////



module userio
(
	input             clk,        // bus clock
	input             reset,      // reset
	input             clk7_en,

	input       [8:1] reg_address_in, // register adress inputs
	input      [15:0] data_in,    // bus data in
	output reg [15:0] data_out,   // bus data out
	input             pot_cnt_en, // one count / scanline
	output            _fire0,     // joystick 0 fire output (to CIA)
	output            _fire1,     // joystick 1 fire output (to CIA)
	input             _fire0_dat,
	input             _fire1_dat,
	input      [15:0] _joy1,      // joystick 1 in (default mouse port)
	input      [15:0] _joy2,      // joystick 2 in (default joystick port)
	input      [15:0] joy_ana1,
	input      [15:0] joy_ana2,
	input       [2:0] mouse_btn,
	input             kms_level,
	input       [1:0] kbd_mouse_type,
	input       [7:0] kbd_mouse_data
);


// register names and adresses
parameter JOY0DAT     = 9'h00a;
parameter JOY1DAT     = 9'h00c;
parameter SCRDAT      = 9'h1f0;
parameter POT0DAT     = 9'h012;
parameter POT1DAT     = 9'h014;
parameter POTINP      = 9'h016;
parameter POTGO       = 9'h034;
parameter JOYTEST     = 9'h036;
parameter KEY_MENU    = 8'h69;
parameter KEY_ESC     = 8'h45;
parameter KEY_ENTER   = 8'h44;
parameter KEY_UP      = 8'h4C;
parameter KEY_DOWN    = 8'h4D;
parameter KEY_LEFT    = 8'h4F;
parameter KEY_RIGHT   = 8'h4E;
parameter KEY_PGUP    = 8'h6c;
parameter KEY_PGDOWN  = 8'h6d;


// local signals
reg   [15:0] _sjoy1;        // synchronized joystick 1 signals
reg   [15:0] _djoy1;        // synchronized joystick 1 signals
reg   [15:0] _sjoy2;        // synchronized joystick 2 signals
reg   [15:0] _djoy2;        // synchronized joystick 2 signals
reg   [15:0] potreg;        // POTGO write
wire  [15:0] mouse0dat;     // mouse counters
reg   [15:0] dmouse0dat;    // docking mouse counters
reg   [15:0] dmouse1dat;    // docking mouse counters
wire         _mleft;        // left mouse button
wire         _mthird;       // middle mouse button
wire         _mright;       // right mouse buttons
reg           joy1enable;   // joystick 1 enable (mouse/joy switch)
wire         test_load;     // load test value to mouse counter
wire  [15:0] test_data;     // mouse counter test value
reg          cd32pad;
reg          joy_swap;

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// POTGO register
always @ (posedge clk) begin
	if (reset) potreg <= 0;
	else if (clk7_en) begin
		if (reg_address_in[8:1]==POTGO[8:1]) potreg[15:0] <= data_in[15:0];
		else potreg[0] <= 0;
	end
end

reg        joy_ana_en;
reg [15:0] ajoy1,ajoy2;

always @(posedge clk) begin
	ajoy1 <= joy_swap ? joy_ana1 : joy_ana2;
	ajoy2 <= joy_swap ? joy_ana2 : joy_ana1;
end

reg   [7:0] pot0x;
reg   [7:0] pot0y;
reg   [7:0] pot1x;
reg   [7:0] pot1y;

// POT[0/1]DAT registers
reg [3:0] potcnt;

// button on the pot pins
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset) begin
      {pot0x, pot0y, pot1x, pot1y} <= 0;
      potcnt <= 4'b0000;
    end else if (potreg[0]) begin
      {pot0x, pot0y, pot1x, pot1y} <= 0;
      potcnt <= 4'b1111;
    end
    else if (pot_cnt_en) begin
		if (joy_ana_en & joy1enable) begin
        if (potcnt[0] && {~ajoy1[ 7],ajoy1[ 6:0]} != pot1y) pot0y <= pot0y + 1'd1; else potcnt[0] <= 0;
        if (potcnt[1] && {~ajoy1[15],ajoy1[14:8]} != pot1x) pot0x <= pot0x + 1'd1; else potcnt[1] <= 0;
      end else begin
        if (!potcap[0]) pot0x <= pot0x + 1'd1;
        if (!potcap[1]) pot0y <= pot0y + 1'd1;
      end
		if (joy_ana_en) begin
        if (potcnt[2] && {~ajoy2[ 7],ajoy2[ 6:0]} != pot1y) pot1y <= pot1y + 1'd1; else potcnt[2] <= 0;
        if (potcnt[3] && {~ajoy2[15],ajoy2[14:8]} != pot1x) pot1x <= pot1x + 1'd1; else potcnt[3] <= 0;
      end else begin
        if (!potcap[2]) pot1x <= pot1x + 1'd1;
        if (!potcap[3]) pot1y <= pot1y + 1'd1;
      end
    end
  end
end

wire joy2_pin5 = ~(potreg[13] & ~potreg[12]);
wire joy1_pin5 = ~(potreg[9]  & ~potreg[8]);

// potcap reg
reg  [4-1:0] potcap;
always @ (posedge clk) begin
	if (reset)
		potcap <= 0;
	else if (clk7_en) begin
		if (cd32pad & ~joy2_pin5) begin
			potcap[3] <= cd32pad2_reg[7];
		end else begin
			potcap[3] <= _djoy2[5] & ~(potreg[15] & ~potreg[14]);
		end
		potcap[2] <= joy2_pin5;

		if(joy1enable & cd32pad & ~joy1_pin5) begin
			potcap[1] <= cd32pad1_reg[7];
		end else begin
			potcap[1] <= _mright & _djoy1[5] & ~(potreg[11] & ~potreg[10]);
		end
		potcap[0] <= _mthird & joy1_pin5;
	end
end

// cd32pad1 reg
reg fire1_d;
always @ (posedge clk) begin
	if (reset) fire1_d <= 1;
	else fire1_d <= _fire0_dat;
end

wire cd32pad1_reg_load  = joy1_pin5;
wire cd32pad1_reg_shift = _fire0_dat && !fire1_d;
reg [8-1:0] cd32pad1_reg;
always @ (posedge clk) begin
	if (reset)                   cd32pad1_reg <= 8'hff;
	else if (cd32pad1_reg_load)  cd32pad1_reg <= {_djoy1[5], _djoy1[4], _djoy1[6], _djoy1[7], _djoy1[8], _djoy1[9], _djoy1[10], 1'b1};
	else if (cd32pad1_reg_shift) cd32pad1_reg <= {cd32pad1_reg[6:0], 1'b0};
end

// cd32pad2 reg
reg fire2_d;
always @ (posedge clk) begin
	if (reset) fire2_d <= 1;
	else fire2_d <= _fire1_dat;
end

wire cd32pad2_reg_load  = joy2_pin5;
wire cd32pad2_reg_shift = _fire1_dat && !fire2_d;
reg [8-1:0] cd32pad2_reg;
always @ (posedge clk) begin
	if (reset)                   cd32pad2_reg <= 8'hff;
	else if (cd32pad2_reg_load)  cd32pad2_reg <= {_djoy2[5], _djoy2[4], _djoy2[6], _djoy2[7], _djoy2[8], _djoy2[9], _djoy2[10], 1'b1};
	else if (cd32pad2_reg_shift) cd32pad2_reg <= {cd32pad2_reg[6:0], 1'b0};
end

wire [15:0] joy1 = joy_ana_en ? {{12{1'b1}}, _joy1[6], 1'b1, _joy1[4], _joy1[5]} : _joy1;
wire [15:0] joy2 = joy_ana_en ? {{12{1'b1}}, _joy2[6], 1'b1, _joy2[4], _joy2[5]} : _joy2;

// input synchronization of external signals
always @ (posedge clk) begin
	_sjoy1 <= joy_swap ? joy1 : joy2;
	_djoy1 <= _sjoy1;
	_sjoy2 <= joy_swap ? joy2 : joy1;
	_djoy2 <= _sjoy2;
end

// port 1 automatic mouse/joystick switch
always @ (posedge clk) begin
	//when left mouse button pushed, switch to mouse (default)
	if (!_mleft || reset) joy1enable = 0;
	//when joystick 1 fire pushed, switch to joystick
	else if (!_sjoy1[4]) joy1enable = 1;
end

// Port 1
always @ (posedge clk) begin
	if (clk7_en) begin
		if (test_load)
			dmouse0dat[7:0] <= 8'h00;
		else if ((!_djoy1[0] && _sjoy1[0] && _sjoy1[2]) || (_djoy1[0] && !_sjoy1[0] && !_sjoy1[2]) || (!_djoy1[2] && _sjoy1[2] && !_sjoy1[0]) || (_djoy1[2] && !_sjoy1[2] && _sjoy1[0]))
			dmouse0dat[7:0] <= dmouse0dat[7:0] + 1'd1;
		else if ((!_djoy1[0] && _sjoy1[0] && !_sjoy1[2]) || (_djoy1[0] && !_sjoy1[0] && _sjoy1[2]) || (!_djoy1[2] && _sjoy1[2] && _sjoy1[0]) || (_djoy1[2] && !_sjoy1[2] && !_sjoy1[0]))
			dmouse0dat[7:0] <= dmouse0dat[7:0] - 1'd1;
		else
			dmouse0dat[1:0] <= {!_djoy1[0], _djoy1[0] ^ _djoy1[2]};
	end
end

always @ (posedge clk) begin
	if (clk7_en) begin
		if (test_load)
			dmouse0dat[15:8] <= 8'h00;
		else if ((!_djoy1[1] && _sjoy1[1] && _sjoy1[3]) || (_djoy1[1] && !_sjoy1[1] && !_sjoy1[3]) || (!_djoy1[3] && _sjoy1[3] && !_sjoy1[1]) || (_djoy1[3] && !_sjoy1[3] && _sjoy1[1]))
			dmouse0dat[15:8] <= dmouse0dat[15:8] + 1'd1;
		else if ((!_djoy1[1] && _sjoy1[1] && !_sjoy1[3]) || (_djoy1[1] && !_sjoy1[1] && _sjoy1[3]) || (!_djoy1[3] && _sjoy1[3] && _sjoy1[1]) || (_djoy1[3] && !_sjoy1[3] && !_sjoy1[1]))
			dmouse0dat[15:8] <= dmouse0dat[15:8] - 1'd1;
		else
			dmouse0dat[9:8] <= {!_djoy1[1], _djoy1[1] ^ _djoy1[3]};
	end
end

// Port 2
always @ (posedge clk) begin
	if (clk7_en) begin
		if (test_load)
			dmouse1dat[7:2] <= test_data[7:2];
		else if ((!_djoy2[0] && _sjoy2[0] && _sjoy2[2]) || (_djoy2[0] && !_sjoy2[0] && !_sjoy2[2]) || (!_djoy2[2] && _sjoy2[2] && !_sjoy2[0]) || (_djoy2[2] && !_sjoy2[2] && _sjoy2[0]))
			dmouse1dat[7:0] <= dmouse1dat[7:0] + 1'd1;
		else if ((!_djoy2[0] && _sjoy2[0] && !_sjoy2[2]) || (_djoy2[0] && !_sjoy2[0] && _sjoy2[2]) || (!_djoy2[2] && _sjoy2[2] && _sjoy2[0]) || (_djoy2[2] && !_sjoy2[2] && !_sjoy2[0]))
			dmouse1dat[7:0] <= dmouse1dat[7:0] - 1'd1;
		else
			dmouse1dat[1:0] <= {!_djoy2[0], _djoy2[0] ^ _djoy2[2]};
	end
end

always @ (posedge clk) begin
	if (clk7_en) begin
		if (test_load)
			dmouse1dat[15:10] <= test_data[15:10];
		else if ((!_djoy2[1] && _sjoy2[1] && _sjoy2[3]) || (_djoy2[1] && !_sjoy2[1] && !_sjoy2[3]) || (!_djoy2[3] && _sjoy2[3] && !_sjoy2[1]) || (_djoy2[3] && !_sjoy2[3] && _sjoy2[1]))
			dmouse1dat[15:8] <= dmouse1dat[15:8] + 1'd1;
		else if ((!_djoy2[1] && _sjoy2[1] && !_sjoy2[3]) || (_djoy2[1] && !_sjoy2[1] && _sjoy2[3]) || (!_djoy2[3] && _sjoy2[3] && _sjoy2[1]) || (_djoy2[3] && !_sjoy2[3] && !_sjoy2[1]))
			dmouse1dat[15:8] <= dmouse1dat[15:8] - 1'd1;
		else
			dmouse1dat[9:8] <= {!_djoy2[1], _djoy2[1] ^ _djoy2[3]};
	end
end

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// data output multiplexer
always @(*) begin
	if ((reg_address_in[8:1]==JOY0DAT[8:1]) && joy1enable)//read port 1 joystick
		data_out[15:0] = {mouse0dat[15:10] + dmouse0dat[15:10],dmouse0dat[9:8],mouse0dat[7:2] + dmouse0dat[7:2],dmouse0dat[1:0]};
	else if (reg_address_in[8:1]==JOY0DAT[8:1])//read port 1 mouse
		data_out[15:0] = {mouse0dat[15:8] + dmouse0dat[15:8],mouse0dat[7:0] + dmouse0dat[7:0]};
	else if (reg_address_in[8:1]==JOY1DAT[8:1])//read port 2 joystick
		data_out[15:0] = dmouse1dat;
	else if (reg_address_in[8:1]==POT0DAT[8:1])
		data_out[15:0] = { pot0y, pot0x };
	else if (reg_address_in[8:1]==POT1DAT[8:1])
		data_out[15:0] = { pot1y, pot1x };
	else if (reg_address_in[8:1]==POTINP[8:1])//read mouse and joysticks extra buttons
		data_out[15:0] = {1'b0, potcap[3],
								1'b0, potcap[2],
								1'b0, potcap[1],
								1'b0, potcap[0],
								8'h00};
	else if (reg_address_in[8:1]==SCRDAT[8:1])//read mouse scroll wheel
		data_out[15:0] = {8'h00,mouse0scr};
	else
		data_out[15:0] = 16'h0000;
end

// assign fire outputs to cia A
assign _fire0 = cd32pad && !cd32pad1_reg_load ? fire1_d : _sjoy1[4] & _mleft;
assign _fire1 = cd32pad && !cd32pad2_reg_load ? fire2_d : _sjoy2[4];

//JB: some trainers writes to JOYTEST register to reset current mouse counter
assign test_load = reg_address_in[8:1]==JOYTEST[8:1] ? 1'b1 : 1'b0;
assign test_data = data_in[15:0];


//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------


//// mouse ////
reg  [ 7:0] xcount;
reg  [ 7:0] ycount;
reg  [ 7:0] mouse0scr;

// mouse counters
always @(posedge clk) begin
	reg old_level;
	reg wheel;
	
	old_level <= kms_level;

	if(reset) begin
		xcount <= 0;
		ycount <= 0;
		mouse0scr <= 0;
		wheel <= 0;
	end else if (test_load && clk7_en) begin
		ycount[7:2] <= test_data[15:10];
		xcount[7:2] <= test_data[7:2];
	end else if (old_level ^ kms_level) begin
		if(kbd_mouse_type == 0) begin
			wheel <= 0;
			xcount[7:0] <= xcount[7:0] + kbd_mouse_data;
		end
		if(kbd_mouse_type == 1) begin
			wheel <= 1;
			if(wheel) mouse0scr <= mouse0scr + kbd_mouse_data;
			else ycount[7:0] <= ycount[7:0] + kbd_mouse_data;
		end
	end
end

// output
assign mouse0dat = {ycount, xcount};

// mouse buttons
assign _mleft  = ~mouse_btn[0];
assign _mright = ~mouse_btn[1];
assign _mthird = ~mouse_btn[2];

endmodule
