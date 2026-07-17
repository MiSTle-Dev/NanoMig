module ws2812 (
	input	     clk,    // input clock source
	input	     reset,  // clock not stable enough
	input [23:0] color,  // requested color
	output reg   data    // output to the interface of WS2812
);

parameter WS2812_NUM 	= 0             ; // LED number of WS2812 (starts from 0)
parameter WS2812_WIDTH 	= 24            ; // WS2812 data bit width
parameter CLK_FRE 	= 28_375_160    ; // CLK frequency (mHZ)

localparam DELAY_1_HIGH	= ((85/5) * CLK_FRE / 20_000_000) - 1; //≈850ns±150ns  1 high level time
localparam DELAY_1_LOW 	= ((40/5) * CLK_FRE / 20_000_000) - 1; //≈400ns±150ns  1 low level time
localparam DELAY_0_HIGH	= ((40/5) * CLK_FRE / 20_000_000) - 1; //≈400ns±150ns  0 high level time
localparam DELAY_0_LOW 	= ((85/5) * CLK_FRE / 20_000_000) - 1; //≈850ns±150ns  0 low level time
localparam DELAY_RESET 	= (CLK_FRE / 10 ) - 1; //0.1s reset time ＞50us

localparam IDLE 	 	= 0; //state machine statement
localparam DATA_SEND  		= 1;
localparam BIT_SEND_HIGH   	= 2;
localparam BIT_SEND_LOW   	= 3;

localparam INIT_DATA = 24'b1111; // initial pattern

reg [ 1:0] state       = 0; // synthesis preserve  - main state machine control
reg [ 8:0] bit_send    = 0; // number of bits sent - increase for larger led strips/matrix
reg [ 8:0] data_send   = 0; // number of data sent - increase for larger led strips/matrix
reg [31:0] clk_count   = 0; // delay control
reg	   WS2812_data_valid = 0;   
reg [23:0] WS2812_data = 0; // WS2812 color data

always@(posedge clk) begin
  if(reset)
    WS2812_data_valid <= 1'b0;
  else begin  
	case (state)
		IDLE:begin
			data <= 0;
			if (clk_count < DELAY_RESET) begin
				clk_count <= clk_count + 1;
            end
			else begin
				clk_count <= 0;
                if (WS2812_data != color || !WS2812_data_valid) begin
		    WS2812_data_valid <= 1'b1;
                    WS2812_data <= color;
                    state <= DATA_SEND;
                end
			end
		end

		DATA_SEND:
			if (data_send > WS2812_NUM && bit_send == WS2812_WIDTH)begin 
                clk_count <= 0;
				data_send <= 0;
				bit_send  <= 0;
				state <= IDLE;
			end 
			else if (bit_send < WS2812_WIDTH) begin
				state    <= BIT_SEND_HIGH;
			end
			else begin
				data_send <= data_send + 9'd1;
				bit_send  <= 0;
				state    <= BIT_SEND_HIGH;
			end
			
		BIT_SEND_HIGH:begin
			data <= 1;

			if (WS2812_data[bit_send]) 
				if (clk_count < DELAY_1_HIGH)
					clk_count <= clk_count + 1;
				else begin
					clk_count <= 0;
					state    <= BIT_SEND_LOW;
				end
			else 
				if (clk_count < DELAY_0_HIGH)
					clk_count <= clk_count + 1;
				else begin
					clk_count <= 0;
					state    <= BIT_SEND_LOW;
				end
		end

		BIT_SEND_LOW:begin
			data <= 0;

			if (WS2812_data[bit_send]) 
				if (clk_count < DELAY_1_LOW) 
					clk_count <= clk_count + 1;
				else begin
					clk_count <= 0;

					bit_send <= bit_send + 9'd1;
					state    <= DATA_SEND;
				end
			else 
				if (clk_count < DELAY_0_LOW) 
					clk_count <= clk_count + 1;
				else begin
					clk_count <= 0;
					
					bit_send <= bit_send + 9'd1;
					state    <= DATA_SEND;
				end
		end
	endcase // case (state)
  end
end // always@ (posedge clk)
   
endmodule
