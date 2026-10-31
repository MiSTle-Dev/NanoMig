$file = "D:\programmier_ordner\FPGA\NanoMig\src\minimig-aga\minimig.v"
$text = [System.IO.File]::ReadAllText($file)
$text = $text.Replace("`r`n", "`n")

# 1. Update aen
$text = $text.Replace(".aen(sel_reg),", ".aen(sel_reg & !audio_ext_selected & !ham_ext_selected),")

# 2. Update int2 in paula
$text = $text.Replace(".int2(int2|(ide_fast ? ide_ext_irq : gayle_irq)),", ".int2(int2|(ide_fast ? ide_ext_irq : gayle_irq)|audio_ext_irq),")
$text = $text.Replace(".int2(int2),", ".int2(int2|audio_ext_irq),")

# 3. Update paula ldata/rdata
$text = $text.Replace(".ldata(ldata),", ".ldata(paula_ldata),")
$text = $text.Replace(".rdata(rdata),", ".rdata(paula_rdata),")

# 4. Search old HAM block
$old_ham = @"
// Experimental HAM register: CPU only ($DFF4D0)
wire ham_ext_selected = (cpu_address_out[23:1] == (24'hDFF4D0 >> 1));
wire ham_ext_access = ham_ext_selected && !dbr && (cpu_rd || cpu_hwr || cpu_lwr);
reg [15:0] ham_control_shadow = 16'h1084;
reg [15:0] ham_control_active = 16'h1084;
always @(posedge clk) begin
 if(reset) begin
  ham_control_shadow <= 16'h1084;
  ham_control_active <= 16'h1084;
 end else begin
  if(ham_ext_access) begin
   if(cpu_hwr) ham_control_shadow[15:8] <= cpu_data_out[15:8];
   if(cpu_lwr) ham_control_shadow[ 7:0] <= cpu_data_out[ 7:0];
  end
  if(sof) ham_control_active <= ham_control_shadow;
 end
end
"@.Replace("`r`n", "`n")

$new_audio_and_ham = @"
// Experimental HAM register: CPU only (Moved behind 16 audio channels to $DFF680)
wire ham_ext_selected = (cpu_address_out[23:1] == (24'hDFF680 >> 1));
wire ham_ext_access = ham_ext_selected && !dbr && (cpu_rd || cpu_hwr || cpu_lwr);
reg [15:0] ham_control_shadow = 16'h1084;
reg [15:0] ham_control_active = 16'h1084;
always @(posedge clk) begin
 if(reset) begin
  ham_control_shadow <= 16'h1084;
  ham_control_active <= 16'h1084;
 end else begin
  if(ham_ext_access) begin
   if(cpu_hwr) ham_control_shadow[15:8] <= cpu_data_out[15:8];
   if(cpu_lwr) ham_control_shadow[ 7:0] <= cpu_data_out[ 7:0];
  end
  if(sof) ham_control_active <= ham_control_shadow;
 end
end

// Audio Extension: 4 Voices ($DFF440-$DFF4BF) with shared ADPCM & DSP AGC mixer
wire audio_ext_selected = (cpu_address_out[23:8] == 16'hDFF4) &&
                          (cpu_address_out[7:1] >= 7'h20) &&
                          (cpu_address_out[7:1] <= 7'h61);
wire audio_ext_access = audio_ext_selected && !dbr && (cpu_rd || cpu_hwr || cpu_lwr);
wire [15:0] audio_ext_rdata;
wire audio_ext_irq;
wire signed [15:0] audio_ext_l, audio_ext_r;
wire audio_dma_req;
wire [31:0] audio_dma_addr;
reg audio_dma_ack;
wire [15:0] audio_dma_data = 16'd0;
wire audio_dma_error = 1'b0;

always @(posedge clk) begin
 if(reset) audio_dma_ack <= 1'b0;
 else audio_dma_ack <= audio_dma_req && !audio_dma_ack;
end

audio_ext #(
 .NUM_VOICES(4)
) AUDIO_EXT (
 .clk(clk),
 .reset(reset),
 .ntsc(~_csync),
 .reg_cs(audio_ext_access),
 .reg_wr(cpu_hwr || cpu_lwr),
 .reg_addr(cpu_address_out[7:1]),
 .reg_be({cpu_hwr, cpu_lwr}),
 .reg_wdata(cpu_data_out),
 .reg_rdata(audio_ext_rdata),
 .irq(audio_ext_irq),
 .dma_req(audio_dma_req),
 .dma_addr(audio_dma_addr),
 .dma_ack(audio_dma_ack),
 .dma_data(audio_dma_data),
 .dma_error(audio_dma_error),
 .sample_l(audio_ext_l),
 .sample_r(audio_ext_r)
);

// Mix Paula + Audio Extension
wire [14:0] paula_ldata, paula_rdata;
wire signed [15:0] paula_l_s = {{1{paula_ldata[14]}}, paula_ldata};
wire signed [15:0] paula_r_s = {{1{paula_rdata[14]}}, paula_rdata};
wire signed [16:0] mix_l = paula_l_s + (audio_ext_l >>> 1);
wire signed [16:0] mix_r = paula_r_s + (audio_ext_r >>> 1);

function [14:0] sat15;
 input signed [16:0] val;
 begin
  if(val > 16383) sat15 = 15'sd16383;
  else if(val < -16384) sat15 = -15'sd16384;
  else sat15 = val[14:0];
 end
endfunction

assign ldata = sat15(mix_l);
assign rdata = sat15(mix_r);
"@.Replace("`r`n", "`n")

if ($text.Contains($old_ham)) {
    $text = $text.Replace($old_ham, $new_audio_and_ham)
    Write-Host "Matched and replaced old HAM block."
} else {
    Write-Error "Could not find old HAM block!"
}

# 5. Add to cpu_data_in
$old_cpu_mux = "((ham_ext_access && cpu_rd) ? ham_control_shadow : 16'h0000)"
$new_cpu_mux = "((ham_ext_access && cpu_rd) ? ham_control_shadow : 16'h0000)`n                     | ((audio_ext_access && cpu_rd) ? audio_ext_rdata : 16'h0000)"
$text = $text.Replace($old_cpu_mux, $new_cpu_mux)

[System.IO.File]::WriteAllText($file, ($text.Replace("`n", "`r`n")))
Write-Host "Done updating minimig.v"
