//--------------------------------------------------------------------------------------------------------
// Module  : sd_rw
// Type    : synthesizable, IP's top
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: A SD-host to initialize SD-card and read or write sector
//           Support CardType   : SDv1.1 , SDv2  or SDHCv2
//--------------------------------------------------------------------------------------------------------

module sd_rw # (
    parameter [2:0] CLK_DIV = 3'd2,
    parameter       SIMULATE = 0
) (
    // rstn active-low, 1:working, 0:reset
    input wire	       rstn,
    // clock
    input wire	       clk,
    // SDcard signals (connect to SDcard), this design do not use sddat1~sddat3.
    output wire	       sdclk,
`ifdef VERILATOR
    output	       sdcmd,
    input	       sdcmd_in,
    output [3:0]       sddat,
    input [3:0]	       sddat_in,
`else
    inout	       sdcmd, 
    inout [3:0]	       sddat,
`endif   
   
    // show card status
    output wire [ 3:0] card_stat, // show the sdcard initialize status
    output reg [ 1:0]  card_type, // 0=UNKNOWN    , 1=SDv1    , 2=SDv2  , 3=SDHCv2
    // user read sector command interface (sync with clk)
    input wire	       rstart, 
    input wire	       wstart, 
    input wire [31:0]  sector,
    output wire	       rbusy,
    output wire	       rdone,
    // sector data output interface (sync with clk)
    output reg	       outen,    // when outen=1, a byte of sector content is read out from outbyte
    output reg [ 8:0]  outaddr,  // outaddr from 0 to 511, because the sector size is 512
    input  [ 7:0]      inbyte,   // a byte to write sector content
    output reg [ 7:0]  outbyte   // a byte of read sector content
);

reg sddatoe;
reg [3:0] sddatout;  
   
// sdcmd tri-state driver
`ifdef VERILATOR
assign sddat = sddatoe ? sddatout : 4'b1111;
wire [3:0] sddatin = sddatoe ? 4'b1111 : sddat_in;
`else
assign sddat = sddatoe ? sddatout : 4'bzzzz;
wire [3:0] sddatin = sddatoe ? 4'b1111 : sddat;
`endif
   
initial {outen, outaddr, outbyte} = 0;

localparam [1:0] UNKNOWN = 2'd0,      // SD card type
                 SDv1    = 2'd1,
                 SDv2    = 2'd2,
                 SDHCv2  = 2'd3;

localparam [15:0] FASTCLKDIV = CLK_DIV;
localparam [15:0] SLOWCLKDIV = (FASTCLKDIV+1) * (SIMULATE ? 16'd5 : 16'd48);

reg        start  = 1'b0;
reg [15:0] precnt = 0;
reg [ 5:0] cmd    = 0;
reg [31:0] arg    = 0;
reg [15:0] clkdiv = SLOWCLKDIV;
reg [31:0] sectoraddr = 0;

wire       busy, done, timeout, syntaxe;
wire[31:0] resparg;

reg        sdv1_maybe = 1'b0;
reg [ 2:0] cmd8_cnt   = 0;
reg [15:0] rca = 0;

localparam [3:0] CMD0      = 4'd0,
                 CMD8      = 4'd1,   // interface condition commands
                 CMD55_41  = 4'd2,   // ACMD ...
                 ACMD41    = 4'd3,   // ... read OCR
                 CMD2      = 4'd4,   // read CID
                 CMD3      = 4'd5,   // get RCA
                 CMD7      = 4'd6,   // select card
                 CMD55_6   = 4'd7,   // ACMD ...
                 READY     = 4'd8,   // was CMD17
                 ACMD6     = 4'd9,   // ... read OCR
                 CMD16     = 4'd10,
                 CMD17     = 4'd11,
                 READING   = 4'd12,
                 CMD24     = 4'd13,
                 WRITING   = 4'd14;     

reg [3:0] sdcmd_stat = CMD0;

localparam [3:0] RWAIT    = 4'd0,
                 RDATA    = 4'd1,
                 RCRC     = 4'd2,
                 RTAIL    = 4'd3,
                 DONE     = 4'd4,
                 RTIMEOUT = 4'd5,
		 WDATA    = 4'd6,
		 WCRC     = 4'd7,
		 WWAITACK = 4'd8,
		 WACK     = 4'd9,
		 WWAIT    = 4'd10,
		 WERR     = 4'd11;
   

reg [3:0] sddat_stat = RWAIT;

reg [31:0] ridx   = 0;
reg [15:0] data_crc[4];     // crc's calculated from data
reg [15:0] read_crc[4];     // crc's received from card
reg [3:0] wdata;   
reg [3:0] wack;
   
   
assign     rbusy  = (sdcmd_stat != READY) ;
assign     rdone  = ((sdcmd_stat == READING) || (sdcmd_stat == WRITING)) && (sddat_stat==DONE);

assign card_stat = sdcmd_stat;

function  [15:0] CalcCrc16;
    input [15:0] crc;
    input [ 0:0] inbit;
begin
    CalcCrc16 = {crc[14:0],crc[15]^inbit} ^ {3'b0,crc[15]^inbit,6'b0,crc[15]^inbit,5'b0};
end
endfunction

// sd clk enable signals
wire ena_n, ena_p;   
   
sdcmd_ctrl u_sdcmd_ctrl (
    .rstn        ( rstn         ),
    .clk         ( clk          ),
    .sdclk       ( sdclk        ),
    .sdcmd       ( sdcmd        ),
`ifdef VERILATOR
    .sdcmd_in    ( sdcmd_in     ),
`endif   
    .ena_n       ( ena_n        ),
    .ena_p       ( ena_p        ),
    .clkdiv      ( clkdiv       ),
    .start       ( start        ),
    .precnt      ( precnt       ),
    .cmd         ( cmd          ),
    .arg         ( arg          ),
    .busy        ( busy         ),
    .done        ( done         ),
    .timeout     ( timeout      ),
    .syntaxe     ( syntaxe      ),
    .resparg     ( resparg      )
);


task set_cmd;
    input [ 0:0] _start;
    input [15:0] _precnt;
    input [ 5:0] _cmd;
    input [31:0] _arg;
//task automatic set_cmd(input _start, input[15:0] _precnt='0, input[5:0] _cmd='0, input[31:0] _arg='0 );
begin
    start  <= _start;
    precnt <= _precnt;
    cmd    <= _cmd;
    arg    <= _arg;
end
endtask

always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        set_cmd(0,0,0,0);
        clkdiv      <= SLOWCLKDIV;
        sectoraddr  <= 0;
        rca         <= 0;
        sdv1_maybe  <= 1'b0;
        card_type   <= UNKNOWN;
        sdcmd_stat  <= CMD0;
        cmd8_cnt    <= 0;
    end else begin
        set_cmd(0,0,0,0);
        if(sdcmd_stat == READING || sdcmd_stat == WRITING) begin
	    // the question is: Do we also want to retry a failed
	    // write? If this happens repeatedly it may wear out the
	    // SD card. So for now i'd say: No retry on write!	   
            if(sddat_stat==RTIMEOUT) begin
                set_cmd(1, 96, 17, sectoraddr);   // retry read
                sdcmd_stat <= CMD17;
            end else if(sddat_stat==DONE)
                sdcmd_stat <= READY;
            else if(sddat_stat==WERR)             // don't retry write
                sdcmd_stat <= READY;
        end else if(~busy) begin
            case(sdcmd_stat)
                CMD0    :   set_cmd(1, (SIMULATE?512:64000),  0,  'h00000000);
                CMD8    :   set_cmd(1,                 512 ,  8,  'h000001aa);
                CMD55_41:   set_cmd(1,                 512 , 55,  'h00000000);
                ACMD41  :   set_cmd(1,                 256 , 41,  'h40100000);
                CMD2    :   set_cmd(1,                 256 ,  2,  'h00000000);
                CMD3    :   set_cmd(1,                 256 ,  3,  'h00000000);
                CMD7    :   set_cmd(1,                 256 ,  7, {rca,16'h0});
                CMD55_6 :   set_cmd(1,                 256 , 55, {rca,16'h0});
                ACMD6   :   set_cmd(1,                 256 ,  6,  'h00000002);
                CMD16   :   set_cmd(1, (SIMULATE?512:64000), 16,  'h00000200);
                READY   :   if(rstart || wstart) begin 
                                set_cmd(1, 96, rstart?17:24, (card_type==SDHCv2) ? sector : (sector<<9) );
                                sectoraddr <= (card_type==SDHCv2) ? sector : (sector<<9);
                                sdcmd_stat <= rstart?CMD17:CMD24;
		            end
            endcase
        end else if(done) begin
            case(sdcmd_stat)
                CMD0    :   sdcmd_stat <= CMD8;
                CMD8    :   if(~timeout && ~syntaxe && resparg[7:0]==8'haa) begin
                                sdcmd_stat <= CMD55_41;
                            end else if(timeout) begin
                                cmd8_cnt <= cmd8_cnt + 3'd1;
                                if (cmd8_cnt == 3'b111) begin
                                    sdv1_maybe <= 1'b1;
                                    sdcmd_stat <= CMD55_41;
                                end
                            end
                CMD55_41:   if(~timeout && ~syntaxe)
                                sdcmd_stat <= ACMD41;
                ACMD41  :   if(~timeout && ~syntaxe && resparg[31]) begin
                                card_type <= sdv1_maybe ? SDv1 : (resparg[30] ? SDHCv2 : SDv2);
                                sdcmd_stat <= CMD2;
                            end else begin
                                sdcmd_stat <= CMD55_41;
                            end
                CMD2    :   if(~timeout && ~syntaxe)
                                sdcmd_stat <= CMD3;
                CMD3    :   if(~timeout && ~syntaxe) begin
                                rca <= resparg[31:16];
                                sdcmd_stat <= CMD7;
                            end
                CMD7    :   if(~timeout && ~syntaxe) begin
                                clkdiv  <= FASTCLKDIV;
                                sdcmd_stat <= CMD55_6;
                            end
                CMD55_6:   if(~timeout && ~syntaxe)
                                sdcmd_stat <= ACMD6;
                ACMD6   :   if(~timeout && ~syntaxe)
                                sdcmd_stat <= CMD16;
                            else
                                sdcmd_stat <= CMD55_6;
                CMD16   :   if(~timeout && ~syntaxe)
                                sdcmd_stat <= READY;
                CMD24   :   if(~timeout && ~syntaxe)
                                sdcmd_stat <= WRITING;
                CMD17   :   if(~timeout && ~syntaxe)
                                sdcmd_stat <= READING;
                            else
                                set_cmd(1, 128, 17, sectoraddr);   // retry
                default :
		  ;	      
            endcase
        end
    end

integer i;   
   
always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        outen   <= 1'b0;
        outaddr <= 0;
        outbyte <= 0;
        sddat_stat <= RWAIT;
        ridx    <= 0;
        sddatoe <= 0;
        sddatout <= 4'd15;       
    end else begin
        outen   <= 1'b0;
        if(sdcmd_stat!=WRITING && sdcmd_stat!=CMD17 && sdcmd_stat!=READING ) begin
 	    // neither writing, nor reading nor waiting for read data -> stay in RWAIT state
            sddat_stat <= RWAIT;
            ridx   <= 0;
        end else begin
            case(sddat_stat)
                RWAIT   : begin
		    // received a write command
		    if(sdcmd_stat == WRITING) begin
		        // data is written on the falling sd clock
		        if(ena_n) begin
                           sddat_stat <= WDATA;
		       
                           for(i=0;i<4;i=i+1) data_crc[i] <= 16'h0000;
                           ridx   <= 0;
                           outaddr<= 0;
			   
		           { sddatoe, sddatout } <= 5'b10000;      // drive data output and send start bit 
			end
		    end 
		   
		    // data is being read on the rising sd clock
		    else if(ena_p) begin
		       // This only starts after read command has been sent
                       if(~sddatin[0]) begin
                          sddat_stat <= RDATA;
                          ridx   <= 0;
                          for(i=0;i<4;i=i+1) data_crc[i] <= 16'h0000;
                       end else begin
			  // according to SD datasheet, 1ms is
			  // enough to wait for DAT result, here, we
			  // set timeout to 1000000 clock cycles =
			  // 80ms (when SDCLK=12.5MHz)
                          if(ridx > 1000000) sddat_stat <= RTIMEOUT;
                          ridx   <= ridx + 1;
		       end
                    end
                end // case: RWAIT
	      
	        // data is being written on the falling sd clock
	        WDATA : if(ena_n) begin
		   // Data is being received as bytes but written to sd card
		   // in 4-bit chunks.		   
                    if(ridx[0] == 1'b0) begin
                       for(i=0;i<4;i=i+1) 
			  data_crc[i] <= CalcCrc16(data_crc[i], inbyte[i+4]);
		       sddatout <= inbyte[7:4];		       
		       wdata <= inbyte[3:0];
		    end else begin
                       for(i=0;i<4;i=i+1) 
			 data_crc[i] <= CalcCrc16(data_crc[i], wdata[i]);
		       sddatout <= wdata;
                       outaddr<= ridx[9:1]+9'd1;
		    end
		     
                    if(ridx >= 128*8-1) begin
                        sddat_stat <= WCRC;
                        ridx   <= 0; 
                    end else begin
                        ridx   <= ridx + 1;
                    end
		end
	      
	        // data CRC is being written on the falling sd clock
	        WCRC : if(ena_n) begin
                   outaddr <= 9'd0;

		   if(ridx < 2*8)
		     for(i=0;i<4;i=i+1) 
		       sddatout[i] <= data_crc[i][4'd15 - ridx[3:0]];
		   else if(ridx == 2*8)
		     sddatout <= 4'hf;		   
		   else // ridx == 2*8+1
                     sddatoe <= 0;	// stop driving data output
		   
                    if(ridx >= 2*8+1) begin
                        sddat_stat <= WWAITACK;
                        ridx   <= 0; 
                    end else begin
                        ridx   <= ridx + 1;
                    end
		end

	        // wait to read ack on rising sd clock edge
	        WWAITACK : if(ena_p) begin
		   if(sddatin[0] == 0) begin
		      sddat_stat <= WACK;
                      ridx   <= 0; 
		   end else if(ridx > 10000000) begin
		      sddat_stat <= WERR;   // write timeout
		      ridx   <= 0; 
		   end else begin
                      ridx   <= ridx + 1;
		   end
		end
	      
	        // read ack on rising sd clock edge
	        WACK : if(ena_p) begin
                    wack[ridx[1:0]] <= sddatin[0];
                    if(ridx >= 4-1) begin
                        sddat_stat <= WWAIT;
                        ridx   <= 0; 
                    end else begin
                        ridx   <= ridx + 1;
                    end
		end

	        // wait for not busy on rising sd clock edge
	        WWAIT : if(ena_p) begin
		   // TODO: This is the place to check wack
		   
		   // wait for not being busy anymore
		   if(sddatin[0] == 1) begin
		      sddat_stat <= RTAIL;
                      ridx   <= 0; 
		   end else if(ridx > 1000000) begin
		      sddat_stat <= WERR;   // busy timeout
		      ridx   <= 0; 
		   end else begin
                      ridx   <= ridx + 1;
		   end
		end 

	        // read the payload itself on rising sd clock edge
                RDATA : if(ena_p) begin
		    if(ridx[0]) outbyte[3:0] <= sddatin;
		    else        outbyte[7:4] <= sddatin;
                    for(i=0;i<4;i=i+1) data_crc[i] <= CalcCrc16(data_crc[i], sddatin[i]);
		   
                    if(ridx[0] == 1) begin
                        outen  <= 1'b1;
                        outaddr<= ridx[9:1];
                    end
                    if(ridx >= 128*8-1) begin
                        sddat_stat <= RCRC;
                        ridx   <= 0; 
                        for(i=0;i<4;i=i+1) read_crc[i] <= 16'h0000;
                    end else begin
                        ridx   <= ridx + 1;
                    end
                end // if (ena_p)

	        // read CRC bits on rising sd clock edge
                RCRC : if(ena_p) begin
                   outaddr <= 9'd0;		   
                   for(i=0;i<4;i=i+1) begin
		      read_crc[i][4'd15 - ridx[3:0]] <= sddatin[i];
		   end
		   
                   if(ridx >= 2*8-1) begin
                        sddat_stat <= RTAIL;
                        ridx   <= 0; 
                    end else begin
                        ridx   <= ridx + 1;
		    end
		end // if (ena_p)

	        // wait 64 bits after data transfer ... TODO: check why exactly
                RTAIL   : if(ena_p) begin
                   if (ridx == 1) begin
		      // TODO: On read this would be the moment to compare 
		      // read CRC's data_crc vs. read_crc
	           end		       
                   if (ridx >= 8*8-1) begin
                      sddat_stat <= DONE;
		   end
                   ridx   <= ridx + 1;
                end
	      
            endcase
        end
    end


endmodule

