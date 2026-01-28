/*
    sysctrl.v
 
    generic system control interface from/via the MCU

    TODO: This is currently very core specific. This needs to be
    generic for all cores.
*/

module sysctrl (
  input		    clk,
  input		    reset,

  input		    data_in_strobe,
  input		    data_in_start,
  input [7:0]	    data_in,
  output reg [7:0]  data_out,

  // interrupt interface
  output	    int_out_n,
  input [7:0]	    int_in,
  output reg [7:0]  int_ack,

  input [1:0]	    buttons, // S0 and S1 buttons on Tang Nano 20k

  output reg [1:0]  leds, // two leds can be controlled from the MCU
  output reg [23:0] color, // a 24bit BRG color to e.g. be used to drive the ws2812

  // values that can be configured by the user		
  output reg	    system_reset,
  output reg [1:0]  system_floppy_drives,
  output reg	    system_floppy_wrprot,
  output reg	    system_floppy_turbo,
  output reg [1:0]  system_chipset,
  output reg	    system_video_mode,
  output reg	    system_video_wide,
  output reg	    system_ide_enable,
  output reg [1:0]  system_video_filter,
  output reg [1:0]  system_video_scanlines,
  output reg [1:0]  system_chipmem,
  output reg [1:0]  system_slowmem,
  output reg [1:0]  system_fastmem,
  output reg	    system_joy_swap
);

reg [3:0] state;
reg [7:0] command;
reg [7:0] id;
   
// reverse data byte for rgb   
wire [7:0] data_in_rev = { data_in[0], data_in[1], data_in[2], data_in[3], 
                           data_in[4], data_in[5], data_in[6], data_in[7] };

reg coldboot = 1'b1;
reg sys_int = 1'b1;

// registers to report button interrupts
reg [1:0] buttonsD, buttonsD2;
reg	  buttons_irq_enable;

// the system control interrupt or any other interrupt (e,g sdc, hid, ...)
// activates the interrupt line to the MCU by pulling it low
assign int_out_n = (int_in != 8'h00 || sys_int)?1'b0:1'b1;

// by default system is in reset
reg main_reset = 1'b1;   
assign system_reset = main_reset;  

reg [31:0] main_reset_timeout;   

// include the menu rom derived from amiga.xml
reg [11:0] menu_rom_addr;
reg  [7:0] menu_rom_data;

// generate hex e.g.: 
// gzip -nc amiga.xml > amiga.xml.gz
// xxd -c1 -p amiga.xml.gz > amiga_xml.hex
reg [7:0] amiga_xml[1024];
initial $readmemh("amiga_xml.hex", amiga_xml);
   
always @(posedge clk) 
     menu_rom_data <= amiga_xml[menu_rom_addr];

// process mouse events
always @(posedge clk) begin  
   if(reset) begin
      state <= 4'd0;      
      leds <= 2'b00;        // after reset leds are off
      color <= 24'h000000;  // color black -> rgb led off

      // stay in reset for about 3 seconds or until MCU releases reset
      main_reset <= 1'b1;   
      main_reset_timeout <= 3 * 32'd28_000_000;      

      buttons_irq_enable <= 1'b1;  // allow buttons irq
      int_ack <= 8'h00;
      coldboot = 1'b1;      // reset is actually the power-on-reset
      sys_int = 1'b1;       // coldboot interrupt

      // OSD value defaults. These should be sane defaults, but the MCU
      // will very likely override these early
      system_floppy_drives <= 2'd0;
      system_floppy_turbo <= 1'b1;      
      system_floppy_wrprot <= 1'b1;      
      system_chipset <= 2'd2;      
      system_video_mode <= 1'b0;      
      system_video_wide <= 1'b0;      
      system_video_filter <= 2'd0;      
      system_video_scanlines <= 2'd0;      
      system_chipmem <= 2'd0;      
      system_slowmem <= 2'd1;      
      system_fastmem <= 2'd0;      
      system_ide_enable <= 1'b0;
      system_joy_swap <= 1'b1;
   end 
   else 
   begin // if (reset)
      //  bring button state into local clock domain
      buttonsD <= buttons;
      buttonsD2 <= buttonsD;

      // release main reset after timeout
      if(main_reset_timeout) begin
	 main_reset_timeout <= main_reset_timeout - 32'd1;

	 if(main_reset_timeout == 32'd1) begin
	    main_reset <= 1'b0;

	    // BRG LED yellow if no MCU has responded
	    color <= 24'h000202;
	 end
      end
      
      int_ack <= 8'h00;

      // iack bit 0 acknowledges the coldboot notification
      if(int_ack[0]) sys_int <= 1'b0;      

      // monitor buttons for changes and raise interrupt
      if(buttons_irq_enable) begin
        if(buttonsD2 != buttonsD) begin
            // irq_enable prevents further interrupts until
            // the button state has actually been read by the MCU
            sys_int <= 1'b1;
            buttons_irq_enable <= 1'b0;
        end
      end
     
      if(data_in_strobe) begin      
        if(data_in_start) begin
            state <= 4'd0;
            command <= data_in;
	    menu_rom_addr <= 12'h000;
            data_out <= 8'h00;
        end else begin
            if(state != 4'd15) state <= state + 4'd1;
	    
            // CMD 0: status data
            if(command == 8'd0) begin
                // return some pattern that would not appear randomly
	        // on e.g. an unprogrammed device
                if(state == 4'd0) data_out <= 8'h5c;   // \ magic marker to identify a valid
                if(state == 4'd1) data_out <= 8'h42;   // / FPGA core
                if(state == 4'd2) data_out <= 8'h00;   // core id 0 = Generic core
            end
	   
            // CMD 1: there are two MCU controlled LEDs
            if(command == 8'd1) begin
                if(state == 4'd0) leds <= data_in[1:0];
            end

            // CMD 2: a 24 color value to be mapped e.g. onto the ws2812
            if(command == 8'd2) begin
                if(state == 4'd0) color[15: 8] <= data_in_rev;
                if(state == 4'd1) color[ 7: 0] <= data_in_rev;
                if(state == 4'd2) color[23:16] <= data_in_rev;
            end

            // CMD 3: return button state
            if(command == 8'd3) begin
               data_out <= { 6'b000000, buttons };;
	       // re-enable interrupt once state has been read
               buttons_irq_enable <= 1'b1;
            end

            // CMD 4: config values (e.g. set by user via OSD)
            if(command == 8'd4) begin
               // second byte can be any character which identifies the variable to set 
               if(state == 4'd0) id <= data_in;

	       // Amiga/Nanomig specific control values
                if(state == 4'd1) begin
                   // Value "R": reset(1) or run(0)
                   if(id == "R") begin
		      main_reset <= data_in[0];
		      // cancel out-timeout if MCU is active
		      main_reset_timeout <= 32'd0;
		   end
		   
		   // Value "D": 1(0) to 4(3) floppy drives
		   if(id == "D") system_floppy_drives <= data_in[1:0];
		   // Value "S": normal(0) or turbo(1) floppy
		   if(id == "S") system_floppy_turbo <= data_in[0];
		   // Value "P": write enabled(0) or write protected(1) floppy
		   if(id == "P") system_floppy_wrprot <= data_in[0];
		   // Value "C": chipset OCS-A500(0), OCS-A1000(1) or ECS(2)
		   if(id == "C") system_chipset <= data_in[1:0];
		   // Value "F": video filter none(0), h(1), v(2) or h+v(3)
		   if(id == "F") system_video_filter <= data_in[1:0];
		   // Value "V": PAL(0) or NTSC(1) video
		   if(id == "V") system_video_mode <= data_in[0];
		   // Value "W": normal(0) or wide screen(1) video
		   if(id == "W") system_video_wide <= data_in[0];
		   // Value "L": Scanlines off(0) or on(1)
		   if(id == "L") system_video_scanlines <= data_in[1:0];
		   // Value "Y": Chipmem 512k(0), 1M(1), 1.5M(2) or 2M(2)
		   if(id == "Y") system_chipmem <= data_in[1:0];
		   // Value "X": Slowmem none(0), 512k(1), 1M(2) or 1.5M(3)
		   if(id == "X") system_slowmem <= data_in[1:0];
		   // Value "Q": Fastmem none(0), 2M(1) or 4M(2)
		   if(id == "Q") system_fastmem <= data_in[1:0];
		   // Value "I": IDE disabled(0) or enabled(1)
		   if(id == "I") system_ide_enable <= data_in[0];
		   // value "J": Swap Joyst off(0) on(1)
		   if(id == "J") system_joy_swap <= data_in[0];
                end
            end

            // CMD 5: interrupt control
            if(command == 8'd5) begin
                // second byte acknowleges the interrupts
                if(state == 4'd0) int_ack <= data_in;

	        // interrupt[0] notifies the MCU of a FPGA cold boot e.g. if
                // the FPGA has been loaded via USB
                data_out <= { int_in[7:1], sys_int };
            end
	   
            // CMD 6: read system interrupt source
            if(command == 8'd6) begin
                // bit[0]: coldboot flag
	        // bit[2]: buttons state change has been detected
                data_out <= { 5'b0000, !buttons_irq_enable, 1'b0, coldboot };
                // reading the interrupt source acknowledges the coldboot notification
                if(state == 4'd0) coldboot <= 1'b0;            
            end

	    // CMD 7: port in/out, currently unused in amiga
	   
            // CMD 8: read (menu) config
            if(command == 8'd8) begin
	       data_out <= menu_rom_data;
	       menu_rom_addr <= menu_rom_addr + 12'd1;		  
	    end
         end
      end
   end
end
    
endmodule
