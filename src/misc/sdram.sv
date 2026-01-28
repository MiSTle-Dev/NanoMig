//
// sdram.sv
//
// sdram controller implementation for the MiSTer SDRAM, the TN20k etc
// 
// Copyright (c) 2024 Till Harbaum <till@harbaum.org> 
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//

// This should work for various RAM sized in 16 or 32 data widths. 
//
// Example 1: TN20k internal sdram
// 32 data, 4 dqm, 11 RAS, 2 bank, 8 CAS 
//     -> 2^(11+2+8)*(32/8) = 8388608 = 8MB
// address map:  BA:21..20 RAS:19..9 CAS:8..1  data mux: 0
//
// Example 2: MiSTer RAM module
// 16 data, 2 dqm, 13 RAS, 2 bank, 9 CAS
//     -> 2^(13+2+9)*(16/8) = 33554432 = 32MB
// address map:  BA:--  RAS:21..9 CAS:8..0  no data mux


module sdram #(parameter DATA_WIDTH=16, RASCAS_DELAY=1, RAS_WIDTH=13, CAS_WIDTH=9) (
	inout reg [DATA_WIDTH-1:0] sd_data, // 16/32 bit bidirectional data bus
	output reg [RAS_WIDTH-1:0] sd_addr, // multiplexed address bus
	output reg [(DATA_WIDTH/8)-1:0]  sd_dqm, // two/four byte masks
	output reg [1:0]  sd_ba,  // four banks
	output		  sd_cs,  // a single chip select
	output		  sd_we,  // write enable
	output		  sd_ras, // row address select
	output		  sd_cas, // columns address select

	// cpu/chipset interface
	input		  clk,
	input		  reset_n, // init signal after FPGA config to initialize RAM

	output		  ready,   // ram is ready and has been initialized
        input		  sync,
	input		  refresh, // chipset requests a refresh cycle
	input [15:0]	  din,     // data input from chipset/cpu
	output reg [15:0] dout,
	input [21:0]	  addr,    // 22 bit word address for 8MB
	input [1:0]	  ds,      // upper/lower data strobe
	input		  cs,      // cpu/chipset requests read/wrie
	input		  we,      // cpu/chipset requests write

	input [15:0]	  p2_din,  // data input from chipset/cpu
	output reg [15:0] p2_dout,
	input [21:0]	  p2_addr, // 22 bit word address
	input [1:0]	  p2_ds,   // upper/lower data strobe
	input		  p2_cs,   // cpu/chipset requests read/wrie
	input		  p2_we,   // cpu/chipset requests write
	output reg        p2_ack
);
`default_nettype none

localparam BURST_LENGTH   = 3'b000; // 000=1, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd2;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write

localparam MODE = { 1'b0, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 

// calculate bit array and offsets for the different ram configurations
localparam DQM_WIDTH = (DATA_WIDTH/8);     // number of DQM bits (4 for 32 data bits, 2 for 16 bits)   
// the unused (off) dqm bits are none for DATA_WIDTH=16 and 2'11 for DATA_WIDTH=32
localparam DQM_OFF = {(DQM_WIDTH-2){1'b1}};

// expand to from 22 to 32 address bits internally to be able to drive bigger rams as well
// and shift one bit for 32 bit data bus as addr[0] is used to multiplex between
// both 16 bit data words
localparam ADDR_BASE = (DATA_WIDTH==32)?1:0;
wire [31:0] addr32 = { {(10+ADDR_BASE){1'b0}}, addr[21:ADDR_BASE]};
wire [31:0] p2_addr32 = { {(10+ADDR_BASE){1'b0}}, p2_addr[21:ADDR_BASE]};

// CAS addr32[CAS_WIDTH-1:0]
// RAS addr32[RAS_WIDTH+CAS_WIDTH-1:CAS_WIDTH]
// BA  addr32[RAS_WIDTH+CAS_WIDTH+1:RAS_WIDTH+CAS_WIDTH]
// during CAS, sd_addr[12:10] needs to be 3'b001 and

// TN20k with RAS_WIDTH=11, CAS_WIDTH=8 and DATA_WIDTH=32
//   CAS =   addr32[7:0] =   addr[8:1]
//   RAS =  addr32[18:8] =  addr[19:9]
//   BA  = addr32[20:19] = addr[21:20]
   
// MiSTer module with RAS_WIDTH=13, CAS_WIDTH=9 and DATA_WIDTH=16
//   CAS =   addr32[8:0] =   addr[8:0]
//   RAS =  addr32[21:9] =  addr[21:9]
//   BA  = addr32[23:22] =       2'b00
   
// ---------------------------------------------------------------------
// ------------------------ cycle state machine ------------------------
// ---------------------------------------------------------------------

// The state machine runs at 32Mhz synchronous to the sync signal.
localparam STATE_IDLE      = 4'd0;   // first state in cycle
localparam STATE_CMD_CONT  = STATE_IDLE + RASCAS_DELAY; // command can be continued
localparam STATE_READ      = STATE_CMD_CONT + CAS_LATENCY + 4'd1;
localparam STATE_LAST      = 4'd6;  // last state in cycle
   
// Cycle pattern:
// 0 - STATE_IDLE - wait for 7MHz clock, perform RAS if CS is asserted
// 1 -              (read)                   (write) 
// 2 - perform CAS                           Drive bus
// 3 - 
// 4 -            - (chip launches data)
// 5 - STATE_READ - latch data
// 6 -
// 7 -
// 8 -
// 9 -
// 10 -
// 11 - STATE LAST - return to IDLE state

// ---------------------------------------------------------------------
// --------------------------- startup/reset ---------------------------
// ---------------------------------------------------------------------

reg [3:0] state;
reg [4:0] init_state;

// wait 1ms (32 8Mhz cycles) after FPGA config is done before going
// into normal operation. Initialize the ram in the last 16 reset cycles (cycles 15-0)
assign ready = !(|init_state);
   
// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

// all possible commands
localparam CMD_NOP             = 3'b111;
localparam CMD_ACTIVE          = 3'b011;
localparam CMD_READ            = 3'b101;
localparam CMD_WRITE           = 3'b100;
localparam CMD_BURST_TERMINATE = 3'b110;
localparam CMD_PRECHARGE       = 3'b010;
localparam CMD_AUTO_REFRESH    = 3'b001;
localparam CMD_LOAD_MODE       = 3'b000;

reg [3:0] sd_cmd;   // current command sent to sd ram
// drive control signals according to current command
assign sd_cs  = 1'b0;
assign sd_ras = sd_cmd[2];
assign sd_cas = sd_cmd[1];
assign sd_we  = sd_cmd[0];

// drive data to SDRAM on write
reg [DATA_WIDTH-1:0] to_ram;
   
reg drive_dq;

assign sd_data = drive_dq ? to_ram : {DATA_WIDTH{1'bz}};

localparam PORT1=2'b00;
localparam PORT2=2'b01;
localparam PORTREFRESH=2'b10;
localparam PORTIDLE=2'b11;
reg [1:0] sdram_port;
localparam SYNCD = 2;

always @(posedge clk) begin
   reg [SYNCD:0] syncD;   
   sd_cmd <= CMD_NOP;  // default: idle

   drive_dq <= 1'b0;
   // init state machines runs once reset ends
   if(!reset_n) begin
      init_state <= 5'h1f;
      state <= STATE_IDLE;      
      p2_ack <= 1'b0;
   end else begin
      if(init_state != 0)
        state <= state + 3'd1;
      
      if((state == STATE_LAST) && (init_state != 0))
        init_state <= init_state - 5'd1;
   end
   
   if(init_state != 0) begin
      syncD <= 0;     
      
      // initialization takes place at the end of the reset
      if(state == STATE_IDLE) begin
	 
	 if(init_state == 13) begin
	    sd_cmd <= CMD_PRECHARGE;
	    sd_addr[10] <= 1'b1;      // precharge all banks
	 end
	 
	 if(init_state == 2) begin
	    sd_cmd <= CMD_LOAD_MODE;
	    sd_addr <= MODE;
	 end
	 p2_ack <= 1'b0;	 
      end
   end else begin
      // add a delay tp the chipselect which in fact is just the beginning
      // of the 7MHz bus cycle
      syncD <= { syncD[SYNCD-1:0], sync };      
      
      // normal operation, start on ... 
      if(state == STATE_IDLE) begin
	 sdram_port <= PORTIDLE;
        // start a ram cycle at the rising edge of sync. In case of NanoMig
	// this is actually the rising edge of the 7Mhz clock
        if (!syncD[SYNCD] && syncD[SYNCD-1]) begin
          state <= 3'd1;

           if(cs) begin
              if(!refresh) begin
		 // RAS phase
		 sdram_port <= PORT1;
		 sd_cmd <= CMD_ACTIVE;

		 // TODO TN20k: addr 19:9, ba 21:20
		 // MiSTer: a 21:9, ba '00
		 sd_addr <= addr32[RAS_WIDTH+CAS_WIDTH-1:CAS_WIDTH];		 
		 sd_ba <= addr32[RAS_WIDTH+CAS_WIDTH+1:RAS_WIDTH+CAS_WIDTH];
 
	         if(!we) sd_dqm <= {DQM_WIDTH{1'b0}};
		 else    sd_dqm <= addr[0]?{DQM_OFF,ds}:{ds,DQM_OFF};
              end else begin
		 sd_cmd <= CMD_AUTO_REFRESH;
		 sdram_port <= PORTREFRESH;
	      end
	   end else if(p2_cs) begin
	      sdram_port <= PORT2;
	      sd_cmd <= CMD_ACTIVE;

	      sd_addr <= p2_addr32[RAS_WIDTH+CAS_WIDTH-1:CAS_WIDTH];		 
	      sd_ba <= p2_addr32[RAS_WIDTH+CAS_WIDTH+1:RAS_WIDTH+CAS_WIDTH];

	      // TODO sd_addr <= p2_addr[21:9];	      
	      // TODO sd_ba <= 2'b00;	      
	      if(!p2_we) sd_dqm <= {DQM_WIDTH{1'b0}};
	      else sd_dqm <= p2_addr[0]?{DQM_OFF,p2_ds}:{p2_ds,DQM_OFF};;
           end else
	     sd_cmd <= CMD_NOP;	   
        end
      end else begin
         // always advance state unless we are in idle state
         state <= state + 3'd1;
	 sd_cmd <= CMD_NOP;
	 
         // -------------------  cpu/chipset read/write ----------------------	 
         // CAS phase 
         if(state == STATE_CMD_CONT) begin
	    case(sdram_port)
	      PORT1 : begin
		 if(cs) begin
		    sd_cmd <= we?CMD_WRITE:CMD_READ;
		    sd_addr[RAS_WIDTH-1:0] <= {RAS_WIDTH{1'b0}};
		    sd_addr[10] <= 1'b1;
		    sd_addr[CAS_WIDTH-1:0] <= addr32[CAS_WIDTH-1:0];		    
		    to_ram <= {(DATA_WIDTH/16){din}};
		    drive_dq <= we;
		 end
	      end
	      PORT2 : begin
		 if(p2_cs) begin
		    sd_cmd <= p2_we?CMD_WRITE:CMD_READ;
		    sd_addr[RAS_WIDTH-1:0] <= {RAS_WIDTH{1'b0}};
		    sd_addr[10] <= 1'b1;
		    sd_addr[CAS_WIDTH-1:0] <= p2_addr32[CAS_WIDTH-1:0];
		    to_ram <= {(DATA_WIDTH/16){p2_din}};
		    drive_dq <= p2_we;
		 end
	      end
	      default:
		;
	    endcase
	    //	    end else
         end
	 if(state == STATE_READ) begin
	    case(sdram_port)
	      PORTREFRESH:
		sd_cmd <= CMD_AUTO_REFRESH;
	      PORT1 : 
		 // dout <= sd_data;
	         dout <= addr[0]?sd_data[15:0]:sd_data[DATA_WIDTH-1:DATA_WIDTH-16];
	      PORT2 : begin
		 // p2_dout <= sd_data;
		 p2_dout <= p2_addr[0]?sd_data[15:0]:sd_data[DATA_WIDTH-1:DATA_WIDTH-16];
		 p2_ack <= ~p2_ack;
	      end
	      default:
		;
	    endcase
	 end
	 
	 if(state == STATE_LAST)
	   state <= STATE_IDLE;	 
      end
   end
end
   
endmodule
`default_nettype wire
