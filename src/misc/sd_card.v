//
// sd_card.v - sd card wrapper currently used to interface to sd_rw.v
//
// This mainly multiplexes between the SD card and the core or MCU. The core
// has its own 512 byte sector buffer and will store SD card data such that
// it can internally read and write at any rate. This file also has a 512
// byte sector buffer to allow the same for the MCU communicating via SPI.
//

module sd_card # (
    parameter [2:0] CLK_DIV = 3'd2,
    parameter       SIMULATE = 0
) (
    // rstn active-low, 1:working, 0:reset
    input			  rstn,
    input			  clk,
    output			  sdclk,
`ifdef VERILATOR
	output			  sdcmd,
    input			  sdcmd_in,
    output [3:0]	  sddat,
    input [3:0]		  sddat_in,
`else
    inout			  sdcmd, 
    inout [3:0]		  sddat,
`endif   

    // mcu interface
    input			  data_strobe,
    input			  data_start,
    input [7:0]		  data_in,
    output reg [7:0]  data_out,

    output reg		  irq,
    input			  iack,

    // export sd image size   
    output reg [63:0] image_size,
    // up to four images supported (e.g. 2x floppy, 2xACSI)
    output reg [7:0]  image_mounted,

    // read sector command interface (sync with clk), this once was
    // directly tied to the sd card. Now this goes to the MCU via the
    // MCU interface as the MCU translates sector numbers from those
    // the core tries to use to physical ones inside the file system
    // of the sd card
    input [7:0]		  rstart, // up to eight different sources can request data 
    input [7:0]		  wstart, 
    input [31:0]	  rsector,
    output			  rbusy,
    output			  rdone,

    // sector data output interface (sync with clk)
    input [7:0]		  inbyte,

	output			  outen,   // when outen=1, a byte of sector content
                               // is read out from outbyte
	output [8:0]	  outaddr, // outaddr from 0 to 511, because the
                               // sector size is 512
	output [7:0]	  outbyte  // a byte of sector content
);

wire [3:0] card_stat;  // show the sdcard initialize status
wire [1:0] card_type;  // 0=UNKNOWN    , 1=SDv1    , 2=SDv2  , 3=SDHCv2

reg [7:0] command;
reg [3:0] byte_cnt;  

reg [7:0] image_target; 

reg	  rstart_int;   
reg	  wstart_int;   
reg [31:0] lsector;  

// local buffer to hold one sector to be forwarded to the MCU
reg [8:0]  mcu_tx_cnt;
   
// only export outen if the resulting data is for the core
wire louten;  

// drive outen only if the core reads data for itself
assign outen = (state == CORE_IO && rstart_int)?louten:1'b0;   
   
// Keep track of current sector destination. We cannot use the command
// directly as the MCU may alter this during sector transfer
localparam [2:0] IDLE         = 3'd0,
                 MCU_READ_SD  = 3'd1,   // read from SD
                 MCU_READ_TX  = 3'd2,   // transmit to MCU for read
                 MCU_WRITE_SD = 3'd3,   // write to SD
                 MCU_WRITE_RX = 3'd4,   // receive from MCU for write
                 CORE_IO      = 3'd5;   // core itself does SD card IO

reg [2:0] state; 
wire [7:0] inbyte_int;  

// interrupt handling
wire rstart_any = {|{rstart}};
wire wstart_any = {|{wstart}};
wire start_any = rstart_any || wstart_any;

wire [7:0] doutb;
reg  dinb_we;

`ifdef VERILATOR
sector_dpram #(8, 9) buffer
(
	.clock(clk),

	.address_a(outaddr),
	.wren_a((state == MCU_READ_SD) && louten),
	.data_a(outbyte),
	.q_a(inbyte_int),

	.address_b(mcu_tx_cnt),
	.wren_b(dinb_we),
	.data_b(data_in),
	.q_b(doutb)
);
`else   
sector_dpram buffer(
    .clka(clk),
    .reseta(1'b0), 
    .cea(1'b1), 					
    .ada(outaddr), 
    .wrea((state == MCU_READ_SD) && louten), 
    .dina(outbyte),
    .ocea(1'b1), 
    .douta(inbyte_int),
					
    .clkb(clk), 
    .resetb(1'b0), 
    .ceb(1'b1), 
    .adb(mcu_tx_cnt), 
    .wreb(dinb_we), 
    .dinb(data_in),
    .oceb(1'b1), 
    .doutb(doutb)					
);
`endif
   
always @(posedge clk) begin
   reg	  startD;   
   
   if(!rstn) begin
      irq <= 1'b0;
      startD <= 1'b0;
   end else begin
      startD <= start_any;
	  
      // rising edge of rstart_any raises interrupt
      if(start_any && !startD)
        irq <= 1'b1;
	  
      // iack clears interrupt
      if(iack)
        irq <= 1'b0;
   end   
end
   
// register the rising edge of rstart and clear it once
// it has been reported to the MCU
always @(posedge clk) begin
   if(!rstn) begin
	  byte_cnt <= 4'd15;
      command <= 8'hff;
      rstart_int <= 1'b0;
      wstart_int <= 1'b0;
      image_size <= 64'd0;
      image_mounted <= 8'b00000000;
      state <= IDLE;      
	  dinb_we <=1'b0;
   end else begin
      image_mounted <= 8'b00000000;

      // done from sd reader acknowledges/clears start
      if(rdone) begin
		 rstart_int <= 1'b0;
		 wstart_int <= 1'b0;
      end
	  
	  // buffer writing is triggered via dinb_we
	  dinb_we <=1'b0;
	  if(dinb_we) begin
		 if(mcu_tx_cnt < 9'd511)
		   mcu_tx_cnt <= mcu_tx_cnt + 9'd1;
		 else begin
			wstart_int <= 1'b1;
			state <= MCU_WRITE_SD;
		 end
	  end
	  
      if(data_strobe) begin
         if(data_start) begin
			command <= data_in;
			
			// differentiate between the two reads
			if(data_in == 8'd2 || data_in == 8'd3)
              state <= (data_in == 8'd3)?MCU_READ_SD:CORE_IO;
			
			byte_cnt <= 4'd0;	    
			data_out <= { card_stat, card_type, rbusy, 1'b0 };
		 end else begin
			// SDC CMD 1: STATUS
			if(command == 8'd1) begin
               // request status information, for the MCU it doesn't matter whether
			   // the core wants to write or to read
			   if(byte_cnt == 4'd0) data_out <= rstart | wstart;
			   if(byte_cnt == 4'd1) data_out <= rsector[31:24];
			   if(byte_cnt == 4'd2) data_out <= rsector[23:16];
			   if(byte_cnt == 4'd3) data_out <= rsector[15: 8];
			   if(byte_cnt == 4'd4) data_out <= rsector[ 7: 0];

			   // this command can optionally send additional (debug) data
			   if(byte_cnt == 4'd5) data_out <= { ~rsector[7], 7'd0 };   // indicate that more data is valid
			   if(byte_cnt == 4'd6) data_out <= { 7'b0000000, |wstart};  // optional data to indicate writes
			end
			
			// SDC CMD 2: CORE_RW, CMD 3: MCU_READ
			if(command == 8'd2 || command == 8'd3) begin
               // inform MCU about read state once command has
               // been transferred. Return 0xff until command is
               // complete, then the state of rstart_int, so the MCU
               // can wait for 0 to be read when waiting for
               // sector data to become available
               if(byte_cnt <= 4'd3) data_out <= 8'hff;
               else	                data_out <= { 7'd0, rstart_int ||  wstart_int };
			   
               if(byte_cnt == 4'd0) lsector[31:24] <= data_in;
               if(byte_cnt == 4'd1) lsector[23:16] <= data_in;
               if(byte_cnt == 4'd2) lsector[15: 8] <= data_in;
               if(byte_cnt == 4'd3) begin 
                  lsector[ 7: 0] <= data_in;
				  
				  // distinguish between read and write
				  if(rstart_any || command == 8'd3) rstart_int <= 1'b1;
				  if(wstart_any) wstart_int <= 1'b1;
               end
			   
               // MCU has requested a sector. Start returning data once it arrives
               if(command == 8'd3) begin
                    // If sector has been requested from sd card, rstart_int
                    // has thus been set and all data has arrived, so
                    // rstart_int is reset again, then start mcu transfer
                    if(byte_cnt >= 4'd4) begin
                        if(!rstart_int) begin
                            state <= MCU_READ_TX;
                            mcu_tx_cnt <= 9'd0;
                        end
				  
                        if(state == MCU_READ_TX) begin
                            data_out <= doutb;					 
                            mcu_tx_cnt <= mcu_tx_cnt + 9'd1;
                        end
                    end
                end	       
			end
			
			// SDC CMD 4: INSERTED
			if(command == 8'd4) begin
			   // MCU reports that some image has been inserted. If
			   // the image size is 0, then no image is inserted
			   if(byte_cnt == 4'd0) image_target <= data_in;
			   if(byte_cnt == 4'd1) image_size[63:24] <= { 32'h00000000, data_in };
			   if(byte_cnt == 4'd2) image_size[23:16] <= data_in;
			   if(byte_cnt == 4'd3) image_size[15:8]  <= data_in;
			   if(byte_cnt == 4'd4) begin 
				  image_size[7:0]   <= data_in;
				  if(image_target <= 8'd7)  // images 0..7 are supported
					image_mounted[image_target] <= 1'b1;
			   end
			end
			
			// SDC CMD 5: MCU WRITE
			if(command == 8'd5) begin
			   // MCU requests to write a sector
               if(byte_cnt == 4'd0) lsector[31:24] <= data_in;
               if(byte_cnt == 4'd1) lsector[23:16] <= data_in;
               if(byte_cnt == 4'd2) lsector[15: 8] <= data_in;
               if(byte_cnt == 4'd3) begin 
                  lsector[ 7: 0] <= data_in;
                  mcu_tx_cnt <= 9'd0;		  
                  state <= MCU_WRITE_RX;
               end
			   
			   // send "busy" while transfer is still in progress
			   data_out <= rbusy?8'h01:8'h00; 
			   
			   // data transfer from MCU to buffer
			   if(!wstart_int && state == MCU_WRITE_RX) begin	  
				  // data transfer into local buffer
				  if(byte_cnt > 4'd3) begin
					 // Trigger write to buffer. Writing the buffer is now delayed by
					 // one cycle. Thus the address update is triggered by dinb_we
					 // above.
					 dinb_we <= 1'b1;
				  end 
			   end
			end
			
			// SDC CMD 6: DIRECT is not used/supported
			
			// SDC CMD 7: LARGE FILE INSERTED
			if(command == 8'd7) begin
			   // MCU reports that some large image has been inserted.
			   if(byte_cnt == 4'd0) image_target <= data_in;
			   if(byte_cnt == 4'd1) image_size[63:56] <= data_in;
			   if(byte_cnt == 4'd2) image_size[55:48] <= data_in;
			   if(byte_cnt == 4'd3) image_size[47:40] <= data_in;
			   if(byte_cnt == 4'd4) image_size[39:32] <= data_in;
			   if(byte_cnt == 4'd5) image_size[31:24] <= data_in;
			   if(byte_cnt == 4'd6) image_size[23:16] <= data_in;
			   if(byte_cnt == 4'd7) image_size[15:8]  <= data_in;
			   if(byte_cnt == 4'd8) begin 
				  image_size[7:0]   <= data_in;
				  if(image_target <= 8'd7)  // images 0..7 are supported
					image_mounted[image_target] <= 1'b1;
			   end
			end
			
			if(byte_cnt != 4'd15) byte_cnt <= byte_cnt + 4'd1;    
         end
      end
   end
end
   
sd_rw #(.CLK_DIV(CLK_DIV), .SIMULATE(SIMULATE)) sd_rw (
   // rstn active-low, 1:working, 0:reset
   .rstn(rstn),
   .clk(clk),

   .sdclk(sdclk),
   .sdcmd(sdcmd),
   .sddat(sddat),
`ifdef VERILATOR
   .sdcmd_in(sdcmd_in),
   .sddat_in(sddat_in),
`endif   
							       
   .card_stat(card_stat),
   .card_type(card_type),

   // lsector is the translated rsector into the file on the FAT fs
   .rstart( rstart_int ), 
   .wstart( wstart_int ), 
   .sector( lsector ),
   .rbusy( rbusy ),
   .rdone( rdone ),

   .inbyte((state == CORE_IO)?inbyte:inbyte_int),
   .outen(louten),
   .outaddr(outaddr),
   .outbyte(outbyte)
);

endmodule // sd_card

`ifdef VERILATOR
module sector_dpram #(parameter DATAWIDTH=8, ADDRWIDTH=8)
(
 input 						clock,

 input [ADDRWIDTH-1:0] 		address_a,
 input [DATAWIDTH-1:0] 		data_a,
 input 						wren_a,
 output reg [DATAWIDTH-1:0] q_a,

 input [ADDRWIDTH-1:0] 		address_b,
 input [DATAWIDTH-1:0] 		data_b,
 input 						wren_b,
 output reg [DATAWIDTH-1:0] q_b
);

reg [DATAWIDTH-1:0] ram[0:(1<<ADDRWIDTH)-1];

always @(posedge clock) begin
	if(wren_a) begin
		ram[address_a] <= data_a;
		q_a <= data_a;
	end else begin
		q_a <= ram[address_a];
	end
end

always @(posedge clock) begin
	if(wren_b) begin
		ram[address_b] <= data_b;
		q_b <= data_b;
	end else begin
		q_b <= ram[address_b];
	end
end

endmodule
`endif //  `ifdef VERILATOR

// To match emacs with gw_ide default
// Local Variables:
// tab-width: 4
// End:
