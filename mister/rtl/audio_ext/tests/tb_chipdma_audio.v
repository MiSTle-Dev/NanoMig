`timescale 1ns/1ps
module tb_chipdma_audio;
reg clk=0, reset=1;
always #5 clk=~clk;
reg [1:0] phase=0;
always @(posedge clk) phase<=phase+1'b1;
reg req=0;
reg [31:0] addr=0;
wire ack, error;
wire [15:0] data;
reg akreq=0, cdreq=0;
reg cpu_idle=1,akwrite=0,cdwrite=0;
reg [23:0] akaddr=24'h100;
reg [31:0] cdaddr=32'h100;
reg [7:0] akbyte=0,cdbyte=0;
wire [7:0] akread;
wire akack, cdack, akarm;
wire dcs;
reg dack=0;
wire [28:1] da;
wire dl,du,dwe;
wire [24:1] ca;
wire cl,cu,crw,cdma;
wire [15:0] cw,dw;
integer acount=0,ccount=0,ecount=0,armcount=0;
always @(posedge clk) begin
 dack <= dcs;
 if(akack) acount<=acount+1;
 if(cdack) ccount<=ccount+1;
 if(ack) ecount<=ecount+1;
 if(akarm)armcount<=armcount+1;
 if(!reset && akarm && !dut.claim_now)$fatal(1,"Akiko arm outside claim");
 if(!reset && dut.state==4 && !cpu_idle && (dcs || dut.arb_drive_chip || ack || akack || cdack))
  $fatal(1,"claimed packet granted while CPU busy");
 if(!reset && dut.state==1 && dut.active_is_audio && dcs && (dwe || dl || du))
  $fatal(1,"audio DDR transaction must be a full-word READ");
 if(!reset && dut.state==1 && dut.active_is_audio && dut.ak_unmapped && (dcs || dut.arb_drive_chip))
  $fatal(1,"invalid audio address reached a memory controller");
 if(!reset && dut.state==1 && dut.active_is_audio && dut.arb_drive_chip && (!crw || cl || cu))
  $fatal(1,"audio chip transaction must be a full-word READ");
end
chipdma_arb dut(
 .clk(clk),.reset(reset),.c_7m(phase[1]),
 .chip_in_addr(24'd0),.chip_in_l(1'b1),.chip_in_u(1'b1),
 .chip_in_rw(1'b1),.chip_in_dma(cpu_idle),.chip_in_wr(16'd0),
 .chip_in_long(1'b0),.chip_in_wr2(16'd0),
 .akiko_dma_req(akreq),.akiko_dma_we(akwrite),.akiko_dma_baddr(akaddr),
 .akiko_dma_wbyte(akbyte),.akiko_dma_rbyte(akread),.akiko_dma_ack(akack),.akiko_arm(akarm),
 .cdtv_dma_req(cdreq),.cdtv_dma_we(cdwrite),.cdtv_dma_baddr(cdaddr),
 .cdtv_dma_wbyte(cdbyte),.cdtv_dma_rbyte(),.cdtv_dma_ack(cdack),
 .audio_dma_req(req),.audio_dma_addr(addr),.audio_dma_data(data),
 .audio_dma_ack(ack),.audio_dma_error(error),
 .chip_out_addr(ca),.chip_out_l(cl),.chip_out_u(cu),.chip_out_rw(crw),
 .chip_out_dma(cdma),.chip_out_wr(cw),.chip_out_long(),.chip_out_wr2(),.chip_in_rd(16'hA53C),
 .z2ram_ena(1'b1),.z3ram_base0(5'b00010),.z3ram_ena0(1'b1),
 .z3ram_base1(4'b0010),.z3ram_ena1(1'b1),
 .ddr_out_addr(da),.ddr_out_l(dl),.ddr_out_u(du),.ddr_out_we(dwe),
 .ddr_out_cs(dcs),.ddr_out_wr(dw),.ddr_in_ack(dack),.ddr_in_rd(16'h1234)
);
task readword;
 input [31:0] a;
 input [15:0] expected;
 input expected_error;
 integer cycles;
 begin
  @(negedge clk);addr=a;req=1;cycles=0;
  while(!ack && cycles<200) begin @(negedge clk);cycles=cycles+1;end
  if(!ack || error!==expected_error || data!==expected)
   $fatal(1,"DMA address=%h ack=%b error=%b data=%h",a,ack,error,data);
  req=0;
  repeat(12) @(negedge clk);
 end
endtask
task byte_transfer;
 input cdtv,write_byte,ddr,odd;
 integer cycles;
 reg [31:0] address;
 reg saw_drive;
 begin
  address=(ddr?32'h200100:32'h100)+odd;saw_drive=0;
  @(negedge clk);
  if(cdtv)begin cdaddr=address;cdwrite=write_byte;cdbyte=8'hD7;cdreq=1;end
  else begin akaddr=address;akwrite=write_byte;akbyte=8'hD7;akreq=1;end
  cycles=0;
  while(!(cdtv?cdack:akack) && cycles<200)begin
   @(negedge clk);cycles=cycles+1;
   if(ddr && dcs)begin
    saw_drive=1;
    if(dl!==!odd || du!==odd || dwe!==write_byte || dw!==16'hD7D7 || da[22:1]!==address[22:1])
     $fatal(1,"DDR byte packet changed");
   end
   if(!ddr && dut.arb_drive_chip)begin
    saw_drive=1;
    if(cl!==!odd || cu!==odd || crw!==!write_byte || cw!==16'hD7D7 || ca!==address[24:1])
     $fatal(1,"chip byte packet changed");
   end
  end
  if(cycles==200 || !saw_drive)$fatal(1,"byte transfer timeout");
  if((cdtv && (ack||akack)) || (!cdtv && (ack||cdack)))$fatal(1,"response owner changed");
  if(!cdtv && !write_byte && akread!==(ddr?(odd?8'h34:8'h12):(odd?8'h3C:8'hA5)))
   $fatal(1,"byte endian read failure");
  akreq=0;cdreq=0;repeat(12)@(negedge clk);
 end
endtask
integer client,write_mode,ram,odd,oldarms,oldacks,waitcycles;
reg [28:1] saved_ddr;
initial begin
 repeat(5) @(negedge clk);reset=0;
 readword(32'h100,16'hA53C,0);
 readword(32'h200000,16'h1234,0);
 readword(32'h10000000,16'h1234,0);
 readword(32'h20000000,16'h1234,0);
 readword(32'hDFF040,0,1);
 readword(32'h101,0,1);
 // Every original byte path: Akiko/CDTV, read/write, chip/DDR, even/odd.
 for(client=0;client<2;client=client+1)
  for(write_mode=0;write_mode<2;write_mode=write_mode+1)
   for(ram=0;ram<2;ram=ram+1)
    for(odd=0;odd<2;odd=odd+1)byte_transfer(client,write_mode,ram,odd);
 // Claim while CPU owns memory. The captured Akiko owner and bus cannot
 // change when new live Akiko/CDTV subrequests appear before slot grant.
 @(negedge clk);cpu_idle=0;akaddr=24'h120;akwrite=0;akbyte=8'h6A;akreq=1;oldarms=armcount;
 wait(dut.state==4);@(negedge clk);
 if(armcount!=oldarms+1)$fatal(1,"Akiko claim must pulse dma_arm exactly once");
 repeat(12)begin
  akaddr=24'h200123;akwrite=1;akbyte=8'hFF;cdreq=~cdreq;cdaddr=cdaddr+2;
  @(negedge clk);
  if(dut.ak_addr!==24'h90 || dut.ak_rw!==1 || dut.ak_wr_data!==16'h6A6A || dut.active_is_audio || dut.active_is_cdtv)
   $fatal(1,"claimed Akiko packet/owner changed while waiting");
  if(armcount!=oldarms+1)$fatal(1,"dma_arm repeated before grant");
 end
 cdreq=0;cpu_idle=1;wait(akack);@(negedge clk);akreq=0;
 if(akread!==8'hA5 || armcount!=oldarms+1)$fatal(1,"claimed Akiko response mismatch");
 repeat(12)@(negedge clk);
 // A claimed audio request still completes once if its source cancels. The
 // upper audio engine discards that late answer; no second request is made.
 cpu_idle=0;addr=32'h200120;req=1;oldacks=ecount;
 wait(dut.state==4);@(negedge clk);saved_ddr=da;req=0;addr=32'hDFF040;
 repeat(12)begin
  cdreq=~cdreq;akaddr=akaddr+2;@(negedge clk);
  if(da!==saved_ddr || !dut.active_is_audio || !dut.ak_is_ddr)$fatal(1,"claimed audio packet/owner changed");
 end
 cdreq=0;cpu_idle=1;wait(ack);@(negedge clk);
 if(data!==16'h1234 || error)$fatal(1,"canceled claimed audio response changed");
 repeat(16)@(negedge clk);if(ecount!=oldacks+1)$fatal(1,"canceled packet acknowledged more than once");
 // Reset must abandon an armed, ungranted packet without driving RAM.
 cpu_idle=0;addr=32'h100;req=1;wait(dut.state==4);@(negedge clk);reset=1;req=0;
 repeat(4)@(negedge clk);reset=0;cpu_idle=1;repeat(12)@(negedge clk);
 if(ack||dcs||dut.state!=0)$fatal(1,"reset did not flush claimed packet");
 akwrite=0;cdwrite=0;akaddr=24'h100;cdaddr=32'h100;
 @(negedge clk);akreq=1;cdreq=1;req=1;addr=32'h200000;
 repeat(180) @(negedge clk);
 if(acount<2 || ccount<2 || ecount<8)
  $fatal(1,"Round-robin starvation Akiko=%0d CDTV=%0d audio=%0d",acount,ccount,ecount);
 $display("PASS chipdma audio: chip/Z2/Z3 word reads, invalid addresses, round-robin coexistence");
 $display("PASS DMA pipeline:32bytepaths, CPUbusy claim, packet/owner stability, exact Akiko arm, canceled/reset claims");
 $finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
