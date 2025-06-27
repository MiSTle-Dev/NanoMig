/*
    hid.v
 
    hid (keyboard, mouse etc) interface to the IO MCU
  */

module hid (
  input		   clk,
  input		   reset,

  input		   data_in_strobe,
  input		   data_in_start,
  input [7:0]	   data_in,
  output reg [7:0] data_out,

  // input local db9 port events to be sent to MCU to e.g.
  // be able to control the OSD via joystick connected
  // to the FPGA
  input [5:0]	   db9_port, 
  output reg	   irq,
  input		   iack,

  // output HID data received from USB
  output reg [2:0] mouse_buttons, // mouse buttons
  output reg	   kbd_mouse_level,
  output reg [1:0] kbd_mouse_type,
  output reg [7:0] kbd_mouse_data,

  output reg [7:0] joystick0,
  output reg [7:0] joystick1
);

reg [3:0] state;
reg [7:0] command;  
reg [7:0] device;   // used for joystick
   
reg irq_enable;
reg [5:0] db9_portD;
reg [5:0] db9_portD2;

wire [6:0] amiga_keycode;   
keymap keymap (
 .code  ( data_in[6:0]  ),
 .amiga ( amiga_keycode )
);  
   
// process mouse events
always @(posedge clk) begin
   if(reset) begin
      state <= 4'd0;
      irq <= 1'b0;
      irq_enable <= 1'b0;
      kbd_mouse_level <= 1'b0;      
   end else begin
      db9_portD <= db9_port;
      db9_portD2 <= db9_portD;
      
      // monitor db9 port for changes and raise interrupt
      if(irq_enable) begin
        if(db9_portD2 != db9_portD) begin
            // irq_enable prevents further interrupts until
            // the db9 state has actually been read by the MCU
            irq <= 1'b1;
            irq_enable <= 1'b0;
        end
      end

      if(iack) irq <= 1'b0;      // iack clears interrupt

      if(data_in_strobe) begin      
        if(data_in_start) begin
            state <= 4'd0;
            command <= data_in;
        end else begin
            if(state != 4'd15) state <= state + 4'd1;
	    
            // CMD 0: status data
            if(command == 8'd0) begin
                // return some dummy data for now ...
                if(state == 4'd0) data_out <= 8'h01;   // hid version 1
                if(state == 4'd1) data_out <= 8'h00;   // subversion 0
            end
	   
            // CMD 1: keyboard data
	    // this Amiga variant of hid.v does not maintain a matrix. Instead
	    // it just sends events 
            if(command == 8'd1) begin
                if(state == 4'd0 && amiga_keycode != 7'h7f) begin
		   kbd_mouse_level <= !kbd_mouse_level;
		   kbd_mouse_type <= 2'd2;
		   kbd_mouse_data <= { data_in[7], amiga_keycode };
		end
            end
	       
            // CMD 2: mouse data
            if(command == 8'd2) begin
	        // we need to be careful here. The receiver runs on the 7Mhz clock
	        // and we need to make sure that these two subsequent events don't come
	        // too fast	       
                if(state == 4'd0) mouse_buttons <= data_in[2:0];
                if(state == 4'd1) begin
		   kbd_mouse_level <= !kbd_mouse_level;
		   kbd_mouse_type <= 2'd0;
		   kbd_mouse_data <= data_in;
		end
                if(state == 4'd2) begin
		   kbd_mouse_level <= !kbd_mouse_level;
		   kbd_mouse_type <= 2'd1;
		   kbd_mouse_data <= data_in;
		end
            end

            // CMD 3: receive digital joystick data
            if(command == 8'd3) begin
                if(state == 4'd0) device <= data_in;
                if(state == 4'd1) begin
                    if(device == 8'd0) joystick0 <= data_in;
                    if(device == 8'd1) joystick1 <= data_in;
                end 
            end

            // CMD 4: send digital joystick data to MCU
            if(command == 8'd4) begin
                if(state == 4'd0) irq_enable <= 1'b1;    // (re-)enable interrupt
                data_out <= {2'b00, db9_portD };               
            end

        end
      end
   end
end
    
endmodule
