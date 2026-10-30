//This is the playfield engine.
//It takes the raw bitplane data and generates a
//single or dual playfield
//it also generated the nplayfield valid data signals which are needed
//by the main video priority logic in Denise


module denise_playfields
(
  input  aga,
  input   [8:1] bpldata,         //raw bitplane data in
  input   dblpf,             //double playfield select
  input [2:0] pf2of,        // playfield 2 offset into color table
  input  [6:0] bplcon2,      //bplcon2 (playfields priority)
  output  reg [2:1] nplayfield,  //playfield 1,2 valid data
  output  reg [7:0] plfdata    //playfield data out
);

//local signals
wire pf2pri;            //playfield 2 priority over playfield 1
wire [2:0] pf2p;          //playfield 2 priority code
reg [7:0] pf2of_val;    // playfield 2 offset value

assign pf2pri = bplcon2[6];
assign pf2p = bplcon2[5:3];

always @ (*) begin
  case(pf2of)
    3'd0 : pf2of_val = 8'd0;
    3'd1 : pf2of_val = 8'd2;
    3'd2 : pf2of_val = 8'd4;
    3'd3 : pf2of_val = 8'd8;
    3'd4 : pf2of_val = 8'd16;
    3'd5 : pf2of_val = 8'd32;
    3'd6 : pf2of_val = 8'd64;
    3'd7 : pf2of_val = 8'd128;
  endcase
end

//generate playfield 1,2 data valid signals
always @(*)
begin
  if (dblpf) //dual playfield
  begin
    if (bpldata[7] || bpldata[5] || bpldata[3] || bpldata[1]) //detect data valid for playfield 1
      nplayfield[1] = 1;
    else
      nplayfield[1] = 0;

    if (bpldata[8] || bpldata[6] || bpldata[4] || bpldata[2]) //detect data valid for playfield 2
      nplayfield[2] = 1;
    else
      nplayfield[2] = 0;
  end
  else //single playfield is always playfield 2
  begin
    nplayfield[1] = 0;
    if (bpldata[8:1]!=8'b000000)
      nplayfield[2] = 1;
    else
      nplayfield[2] = 0;
  end
end

//playfield 1 and 2 priority logic
always @(*)
begin
  if (dblpf) //dual playfield
  begin
    if (pf2pri) //playfield 2 (2,4,6) has priority
    begin
      if (nplayfield[2])
        if (aga)
          plfdata[7:0] = {4'b0000,bpldata[8],bpldata[6],bpldata[4],bpldata[2]} + pf2of_val;
        else
          plfdata[7:0] = {4'b0000,1'b1,bpldata[6],bpldata[4],bpldata[2]};
      else if (nplayfield[1])
        plfdata[7:0] = {4'b0000,bpldata[7],bpldata[5],bpldata[3],bpldata[1]};
      else //both planes transparant, select background color
        plfdata[7:0] = 8'b00000000;
    end
    else //playfield 1 (1,3,5) has priority
    begin
      if (nplayfield[1])
        plfdata[7:0] = {4'b0000,bpldata[7],bpldata[5],bpldata[3],bpldata[1]};
      else if (nplayfield[2])
        if (aga)
          plfdata[7:0] = {4'b0000,bpldata[8],bpldata[6],bpldata[4],bpldata[2]} + pf2of_val;
        else
          plfdata[7:0] = {4'b0000,1'b1,bpldata[6],bpldata[4],bpldata[2]};
      else //both planes transparent, select background color
        plfdata[7:0] = 8'b00000000;
    end
  end
  else //normal single playfield (playfield 2 only)
  //OCS/ECS undocumented feature when bpu=5 and pf2pri>5 (Swiv score display)
    if ((pf2p>5) && bpldata[5] && !aga)
      plfdata[7:0] = {8'b00010000};
    else
      plfdata[7:0] = bpldata[8:1];
end


endmodule

