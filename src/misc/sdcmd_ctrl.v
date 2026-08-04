//--------------------------------------------------------------------------------------------------------
// Module  : sdcmd_ctrl
// Type    : synthesizable, IP's sub module
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: sdcmd signal control,
//           instantiated by sd_reader
//--------------------------------------------------------------------------------------------------------

module sdcmd_ctrl (
    input wire	       rstn,
    input wire	       clk,
    // SDcard signals (sdclk and sdcmd)
    output reg	       sdclk,
`ifdef VERILATOR
    output	       sdcmd,
    input	       sdcmd_in,
`else
    inout	       sdcmd,
`endif   
    // config clk freq
    input wire [15:0]  clkdiv,
    output	       ena_n, // falling sd clock edge (writing)
    output	       ena_p, // rising sd clock edge (reading)
		   
    // user input signal
    input wire	       start,
    input wire [15:0]  precnt,
    input wire [ 5:0]  cmd,
    input wire [31:0]  arg,

    // user output signal
    output	       busy,
    output	       done,
    output reg	       timeout,
    output reg	       syntaxe,
    output wire [31:0] resparg
);


initial {timeout, syntaxe} = 0;
initial sdclk = 1'b0;

localparam [15:0] TIMEOUT = 16'd250;

reg sdcmdoe;
reg sdcmdout;

// sdcmd tri-state driver
`ifdef VERILATOR
assign sdcmd = sdcmdoe ? sdcmdout : 1'b1;
wire sdcmdin = sdcmdoe ? 1'b1 : sdcmd_in;
`else
assign sdcmd = sdcmdoe ? sdcmdout : 1'bz;
wire sdcmdin = sdcmdoe ? 1'b1 : sdcmd;
`endif
   
function  [6:0] CalcCrc7;
    input [6:0] crc;
    input [0:0] inbit;
//function automatic logic [6:0] CalcCrc7(input logic [6:0] crc, input logic inbit);
begin
    CalcCrc7 = ( {crc[5:0],crc[6]^inbit} ^ {3'b0,crc[6]^inbit,3'b0} );
end
endfunction

reg [ 5:0] req_cmd;    // request[45:40]
reg [31:0] req_arg;    // request[39: 8]
reg [ 6:0] req_crc;    // request[ 7: 1]

// 1' is the idle state of the command signal. The first '0 bit is
// actually the start bit-47, followed by a 1'bit
wire [47:0] request = {2'b01, req_cmd, req_arg, req_crc, 1'b1};

reg         resp_st;
reg  [ 5:0] resp_cmd;
reg  [31:0] resp_arg;
assign resparg = resp_arg;

reg  [17:0] clkdivr = 18'h3FFFF;
reg  [17:0] clkcnt  = 0;

reg  [15:0] cnt  = 0;

// clock counter states at which the sd clock changes
assign	    ena_n = (clkcnt == clkdivr);
assign	    ena_p = (clkcnt == {clkdivr[16:0],1'b1});
   
reg [2:0] state;
localparam STATE_IDLE     = 3'd0;
localparam STATE_PRECOUNT = 3'd1;
localparam STATE_SEND_REQ = 3'd2;
localparam STATE_WAIT4RES = 3'd3;
localparam STATE_RCV_RES  = 3'd4;
localparam STATE_DONE     = 3'd7;

assign busy = state != STATE_IDLE;
assign done = state == STATE_DONE;   
   
always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        {timeout, syntaxe} <= 0;
        sdclk <= 1'b0;
        {sdcmdoe, sdcmdout} <= 2'b11;  // drive cmd high while no command in progress

        clkdivr <= 18'h3FFFF;                 // initially clock is divided by 256k
        clkcnt  <= 0;
        cnt <= 16'd0;

        state <= STATE_IDLE;       
    end else begin
        {timeout, syntaxe} <= 0;

       // run clock counter up to 2*clkdiv+1, e.g. 
       // clkdiv == 2 -> 0,1,2 ... 5
       // clkdiv == 1 -> run 0,1,2,3
       // With 16Mhz clock and clk_div == 1, this should result in 16/4 = 4Mhz / 250ns
       clkcnt <= ( clkcnt < {clkdivr[16:0],1'b1} ) ? (clkcnt+18'd1) : 18'd0;

       // latch clockdiv at the end of each clock cycle to prevent glitches
       if (clkcnt == 18'd0) clkdivr <= {2'h0, clkdiv};

       // generate sd clock itself. With 
        if (ena_n)        sdclk <= 1'b0;
        else if (ena_p )  sdclk <= 1'b1;

       case(state)         
         STATE_IDLE: begin
            if(start) begin
	       state <= STATE_PRECOUNT;	       
               req_cmd <= cmd;
               req_arg <= arg;
               req_crc <= 0;
               cnt <= precnt;
               {timeout, syntaxe} <= 0;
	    end
         end 
	 
	 STATE_PRECOUNT: begin
	    if( ena_n ) begin
	       if(cnt != 16'd0)	       
		 cnt <= cnt - 16'd1;
	       else begin
		  state <= STATE_SEND_REQ;  // start sending request
		  cnt <= 16'd47;            // 48 request bits
	       end
	    end
	 end
	 
	 STATE_SEND_REQ: begin
	    if( ena_n ) begin
	       if(cnt != 16'hffff) begin
		  cnt <= cnt - 16'd1;
		  sdcmdout <= request[cnt];   // drive cmd bit
		  
		  // calculate the crc during transmission. It's then mapped into request bits 1 to 7
		  if(cnt>=8 && cnt<48) req_crc <= CalcCrc7(req_crc, request[cnt]);
	       end else begin
		  state <= STATE_WAIT4RES;
		  cnt <= TIMEOUT;
		  {sdcmdoe, sdcmdout} <= 2'b01;        // stop driving cmd, prepare for reading
	       end
	    end // if ( ena_n )	   
        end
	 
	 STATE_WAIT4RES: begin
	    // command has been sent, now wait for sd card to pull cmd low
	    if( ena_p ) begin	   
               cnt <= cnt - 16'd1;
               if(~sdcmdin) begin
		  state <= STATE_RCV_RES;		   
		  cnt <= 16'd134;    // 1' + 6 bit command + 32 bit reply + 96 bit ignored (incl crc and stop) = 135
               end else if(cnt == 16'd0) begin
		  state <= STATE_DONE;		   
                  timeout <= 1'b1;   // timeout
	       end	       
	    end
	 end // if ( state == STATE_WAIT4RES )
	 
	 STATE_RCV_RES: begin
	    // receive reply
	    if( ena_p ) begin	      
               cnt <= cnt - 16'd1;
               if(cnt >= 16'd96)
                 {resp_st, resp_cmd, resp_arg} <= {resp_cmd, resp_arg, sdcmdin};
               if(cnt == 16'd0) begin
		  state <= STATE_DONE;		   
                  syntaxe <= resp_st || ((resp_cmd!=req_cmd) && (resp_cmd!=6'h3F) && (resp_cmd!=6'd0));
               end
	    end
         end // if (state == STATE_RCV_RES )
	 
	 STATE_DONE: begin
            {sdcmdoe, sdcmdout} <= 2'b11;  // drive cmd high, again
	    state <= STATE_IDLE;
	 end
       endcase
    end
   
endmodule
