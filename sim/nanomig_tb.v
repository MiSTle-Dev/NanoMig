// nanomig simulation top

module nanomig_tb
  (
   input	 clk, // 28mhz
   output	 clk_7m, 
   output	 clk7_en,
   output	 clk7n_en,
   input	 por,
   input	 reset,
   output	 cpu_reset, 

   // serial output, mainly for diagrom
   output	 uart_tx,

   // signal to e.g. trigger on disk activity
   output	 pwr_led,
   output	 fdd_led,
   output	 hdd_led,
   input	 trigger, 

   // video
   output	 hs_n,
   output	 vs_n,
   output [3:0]	 red,
   output [3:0]	 green,
   output [3:0]	 blue,

   input [7:0]	 memory_config,
   input [2:0]	 fastram_config,
   input [3:0]	 floppy_config,
   input [5:0]	 ide_config,
   
   output	 sdclk,
   output	 sdcmd,
   input	 sdcmd_in,
   output [3:0]	 sddat,
   input [3:0]	 sddat_in,

`ifndef NO_COMPANION
   input	 mcu_data_strobe,
   input	 mcu_data_start,
   input [7:0]	 mcu_data_in,
   output [7:0]	 mcu_data_out,
   output	 mcu_irq,
   input	 mcu_iack,
`endif
   
   // external ram/rom interface
   output [15:0] ram_data, // sram data bus
   input [15:0]	 ramdata_in, // sram data bus in
   output [23:1] ram_address, // sram address bus
   output	 _ram_bhe, // sram upper byte select
   output	 _ram_ble, // sram lower byte select
   output	 _ram_we, // sram write enable
   output	 _ram_oe      // sram output enable
   );
   
// for floppy IO the SD card itself may be included into the simulation or not
wire [7:0]	 sdc_rd;
wire [7:0]	 sdc_wr;
wire [31:0]	 sdc_sector;
wire		 sdc_busy;
wire		 sdc_done;
wire		 sdc_byte_in_strobe;
wire [8:0]	 sdc_byte_addr;
wire [7:0]	 sdc_byte_in_data;
wire [7:0]	 sdc_byte_out_data;

// interface to sd card
wire [63:0]      image_size;   
wire [7:0]       image_mounted;     

wire [2:0]       rom_selected;
wire		 rom_selection_strobe;
wire		 kickrom_size_valid = (image_size == 64'd524288 || image_size == 64'd262144);
wire		 rom_accepted = (rom_selection_strobe && rom_selected == 3'd0) && kickrom_size_valid;
   
// during kick download the ram is not driven by the minimig core itself    
wire [15:0]	 ram_data_i;      // sram data bus
wire [23:1]	 ram_address_i;   // sram address bus
wire		 _ram_bhe_i;      // sram upper byte select
wire		 _ram_ble_i;      // sram lower byte select
wire		 _ram_we_i;       // sram write enable
wire		 _ram_oe_i;       // sram output enable

`ifndef NO_COMPANION
// state machine handling kickstart upload from Companion
reg [2:0]	 kick_upload_state = 3'd0;
reg		 kick_is_256k; 
wire		 rom_download_in_progress = kick_upload_state >= 3'd1 && kick_upload_state <= 3'd3;
   
wire		 rom_data_available;   
wire [7:0]	 rom_data;
reg		 rom_data_strobe;
reg		 rom_data_byte_toggle;
   
reg [7:0]	 rom_data_lowbyte;   
reg [15:0]	 rom_data_word;   
reg [18:1]	 rom_data_addr;   
reg		 rom_data_word_we;

assign ram_data = rom_download_in_progress?rom_data_word:ram_data_i;
`else // !`ifndef NO_COMPANION
assign ram_data = ram_data_i;
wire		 rom_download_in_progress = 1'b0;   
assign ram_address = ram_address_i;  
assign { _ram_bhe, _ram_ble } = { _ram_bhe_i, _ram_ble_i };
assign _ram_we = _ram_we_i;
assign _ram_oe = _ram_oe_i;
`endif
   
`ifndef NO_COMPANION
wire		 minimig_is_accessing_256k_rom = kick_is_256k && (ram_address_i[23:19] == 5'b01111);
assign ram_address = rom_download_in_progress?{5'b01111, rom_data_addr}:
		     minimig_is_accessing_256k_rom?{ram_address_i[23:19],1'b0,ram_address_i[17:1]}:
		     ram_address_i;  

assign { _ram_bhe, _ram_ble } = rom_download_in_progress?{2'b00}:{ _ram_bhe_i, _ram_ble_i };
assign _ram_we = rom_download_in_progress?!rom_data_word_we:_ram_we_i;
assign _ram_oe = rom_download_in_progress?1'b1:_ram_oe_i;

wire [18:1]	 rom_data_addr_max = ((kick_is_256k?'d262144:'d524288)/2)-1;

// The ROM uploader receives ROM data from the Companion and writes it into
// the area of sdram that is reserved for kickstart rom  
always @(posedge clk, posedge por) begin
   if(por) begin
      kick_upload_state <= 3'd0;
      rom_data_word_we <= 1'b0;
   end else begin
      rom_data_strobe <= 1'b0;		 
      if(clk7_en && rom_data_word_we) begin
	 rom_data_word_we <= 1'b0;
	 if(rom_data_addr != rom_data_addr_max)
      	   rom_data_addr <= rom_data_addr + 18'd1;   
      end

      case(kick_upload_state)
	3'd0: begin
	  // FPGA Companion wants to upload a rom to slot 0 with 256k or 512k size
	  if(rom_selection_strobe) begin
	     if(rom_accepted) begin
		$display("nanomig_rb.v: Request kickstart upload, size = %0d", image_size);
		kick_upload_state <= 3'd1;
		kick_is_256k <= (image_size == 64'd262144);
		rom_data_byte_toggle <= 1'b0;
		rom_data_addr <= 18'd0;
	     end else
	       $display("nanomig_tb.v: Kickstart upload rejected, size = %0d", image_size);
	  end
	end

	3'd1: begin
	   // sync to amiga 7 Mhz clock
	   if(clk7n_en)
	     kick_upload_state <= 3'd2;
	end

	3'd2: begin
	   // transfer kickstart from sd card fifo
	   // (byte) data is read on both 7Mhz edges, so 16 bit data is ready
	   // every 7 Mhz edge
	   if(rom_data_available) begin
	      if(clk7n_en && !rom_data_byte_toggle) begin		 
		 rom_data_lowbyte <= rom_data;
		 rom_data_strobe <= 1'b1;  // notify SD card driver that byte has been read
		 rom_data_byte_toggle <= 1'b1;		 
	      end	      
	      if(clk7_en && rom_data_byte_toggle) begin
		 rom_data_word <= { rom_data_lowbyte, rom_data };
		 
		 rom_data_strobe <= 1'b1;  // notify SD card driver that byte has been read
		 rom_data_word_we <= 1'b1; // 16 bit data is ready
		 rom_data_byte_toggle <= 1'b0;		 
		 
		 // check if kickstart is complete
		 if(rom_data_addr == rom_data_addr_max)
		   kick_upload_state <= 3'd3;
	      end
	   end	   
	end // case: 3'd2
	
	3'd3:
	  if(clk7_en) begin
	     $display("nanomig_tb.v: ROM upload complete");		    
	     kick_upload_state <= 3'd4;
	  end

	3'd4:
	  kick_upload_state <= 3'd0;
	
      endcase	 
   end   
end
`else // !`ifndef NO_COMPANION
`define DISABLE_ROM_IMAGE 
`endif   

sd_card #(
    .CLK_DIV(3'd0),                // for 28 Mhz clock
    .SIMULATE(1'b1),
    .IMAGE_FIFO_BITS(9)
) sd_card (
    .rstn(!por),                   // rstn active-low, 1:working, 0:reset
    .clk(clk),                     // clock

    // SD card signals
    .sdclk(sdclk),
    .sdcmd(sdcmd),
    .sdcmd_in(sdcmd_in),
    .sddat(sddat),
    .sddat_in(sddat_in),

    // user read sector command interface (sync with clk)
    .rstart(sdc_rd),
    .wstart(sdc_wr), 
    .rsector(sdc_sector),
    .rbusy(sdc_busy),
    .rdone(sdc_done),

`ifndef NO_COMPANION
    // mcu interface
    .data_strobe(mcu_data_strobe),
    .data_start(mcu_data_start),
    .data_in(mcu_data_in),
    .data_out(mcu_data_out),
    .irq(mcu_irq),
    .iack(mcu_iack),
`endif
	   
    .image_size(image_size),
    .image_mounted(image_mounted),

`ifndef DISABLE_ROM_IMAGE
    // rom download interface
    .rom_image_selected(rom_selected),  // image_size is valid for this
    .rom_image_selection_strobe(rom_selection_strobe),
    .rom_image_accepted(rom_accepted),
    .rom_image_data_available(rom_data_available),
    .rom_image_data(rom_data),
    .rom_image_data_strobe(rom_data_strobe),
`endif
	   
    // sector data output interface (sync with clk)
    .inbyte(sdc_byte_out_data),
    .outen(sdc_byte_in_strobe),  // when outen=1, a byte of sector content is read out from outbyte
    .outaddr(sdc_byte_addr),  // outaddr from 0 to 511, because the sector size is 512
    .outbyte(sdc_byte_in_data)   // a byte of sector content
);
   
nanomig nanomig (
		 // system pins
		 .clk_sys(clk),   // 28.37516 MHz clock
		 .reset(reset || rom_download_in_progress ),
		 .por(por),
		 
		 .cpu_nrst_out(cpu_reset),
		 .clk7_en(clk7_en),
		 .clk7n_en(clk7n_en),

		 .pwr_led(pwr_led),
		 .fdd_led(fdd_led),
		 .hdd_led(hdd_led),

		 .memory_config(memory_config),
		 .fastram_config(fastram_config),
		 .floppy_config(floppy_config),
		 .ide_config(ide_config),
		 
		 .hs(hs_n),
		 .vs(vs_n),
		 .r(red),
		 .g(green),
		 .b(blue),

		 .joystick0(6'b000000),
		 .joystick1(6'b000000),
		 
		 // sd card interface for floppy disk emulation
		 .sdc_img_mounted    ( image_mounted     ),
		 .sdc_img_size       ( image_size        ),  // length of image file		 
		 .sdc_rd(sdc_rd),
		 .sdc_wr(sdc_wr),
		 .sdc_sector(sdc_sector),
		 .sdc_busy(sdc_busy),
		 .sdc_done(sdc_done),
		 .sdc_byte_in_strobe(sdc_byte_in_strobe),
		 .sdc_byte_addr(sdc_byte_addr),
		 .sdc_byte_in_data(sdc_byte_in_data),
		 .sdc_byte_out_data(sdc_byte_out_data),
		 
		 .uart_tx(uart_tx),
		 
		 // (s(d))ram interface
		 .ram_data(ram_data_i),       // sram data bus
		 .ramdata_in(ramdata_in),     // sram data bus in
		 .chip48(48'h0),              // big chip read, needed for AGA only
		 .ram_address(ram_address_i), // sram address bus
		 ._ram_bhe(_ram_bhe_i),       // sram upper byte select
		 ._ram_ble(_ram_ble_i),       // sram lower byte select
		 ._ram_we(_ram_we_i),         // sram write enable
		 ._ram_oe(_ram_oe_i)          // sram output enable
		 );
   
endmodule
