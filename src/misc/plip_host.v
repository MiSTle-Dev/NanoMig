/*
    plip_host.v

    SPI target 5 ("NET") of the MCU interface: host side of plip_peer. The FPGA
    Companion reads frames the Amiga sent, writes frames for the Amiga and
    configures the virtual parallel port. Byte protocol like the other targets
    (the reply to a byte is set by its strobe and shifted out with the next byte):

    first byte    command, the reply to it is stale
    cmd 0 STATUS  reply 1: status {loop, en, tx_valid, rx_valid} (bits 3..0)
                  reply 2: rx_len[10:8], reply 3: rx_len[7:0]
    cmd 1 READ    reply 1: status, reply 2: 0 (ready), reply 3..: frame bytes
    cmd 2 RELEASE any byte: rx buffer free again
    cmd 3 WRITE   data bytes into the tx buffer (index 0..2047), needs tx_valid = 0
    cmd 4 COMMIT  len[10:8], len[7:0]: frame is ready for the Amiga (ignored if
                  tx_valid is still set or the length is 0)
    cmd 5 CONFIG  byte 0: bit 0 = enable virtual port, bit 1 = loopback of $FFFD frames
    cmd 6 STATS   replies after the status: stat_rx, stat_tx, rt_clks (3 x 32 bit, msb first)

    irq is raised when a frame from the Amiga has arrived (rx_valid rises) and when the
    Amiga has fetched a frame (tx_valid falls). iack clears it.
*/

module plip_host (
  input             clk,
  input             reset,

  input             data_strobe,
  input             data_start,
  input [7:0]       data_in,
  output reg [7:0]  data_out,

  output reg        irq,
  input             iack,

  output reg        plip_en,
  output reg        plip_loop,

  // plip_peer host side
  output reg        h_we,
  output reg [10:0] h_waddr,
  output reg [7:0]  h_wdata,
  output reg        h_commit,
  output reg [10:0] h_len,
  input             tx_valid,
  output reg [10:0] h_raddr,
  input [7:0]       h_rdata,
  input             rx_valid,
  input [10:0]      rx_len,
  output reg        h_release,
  input [31:0]      stat_rx,
  input [31:0]      stat_tx,
  input [31:0]      rt_clks
);

reg [7:0]  command;
reg [11:0] cnt;                    // index of the byte after the command, saturates
reg        rx_valid_d, tx_valid_d;

wire [7:0]  status = { 4'b0000, plip_loop, plip_en, tx_valid, rx_valid };
`ifndef PLIP_LITE
wire [95:0] stats  = { stat_rx, stat_tx, rt_clks };
`endif

always @(posedge clk) begin
  h_we <= 1'b0;
  h_commit <= 1'b0;
  h_release <= 1'b0;

  rx_valid_d <= rx_valid;
  tx_valid_d <= tx_valid;

  if(iack) irq <= 1'b0;
  if((rx_valid && !rx_valid_d) || (!tx_valid && tx_valid_d)) irq <= 1'b1;

  if(reset) begin
    plip_en <= 1'b0;
    plip_loop <= 1'b0;
    irq <= 1'b0;
    command <= 8'hff;
    cnt <= 12'd0;
  end else if(data_strobe) begin
    if(data_start) begin
      command <= data_in;
      cnt <= 12'd0;
      data_out <= status;
    end else begin
      if(cnt != 12'hfff) cnt <= cnt + 12'd1;

      case(command)
        8'd0: data_out <= (cnt == 12'd0) ? { 5'b00000, rx_len[10:8] } :
                          (cnt == 12'd1) ? rx_len[7:0] : 8'h00;

        8'd1: if(cnt == 12'd0) begin
                h_raddr <= 11'd0;
                data_out <= 8'h00;
              end else begin
                data_out <= h_rdata;
                h_raddr <= h_raddr + 11'd1;
              end

        8'd2: if(cnt == 12'd0) h_release <= 1'b1;

        8'd3: if(!tx_valid && cnt < 12'd2048) begin
                h_wdata <= data_in;
                h_waddr <= cnt[10:0];
                h_we <= 1'b1;
              end

        8'd4: begin
                if(cnt == 12'd0) h_len[10:8] <= data_in[2:0];
                if(cnt == 12'd1) begin
                  h_len[7:0] <= data_in;
                  if(!tx_valid && !(h_len[10:8] == 3'd0 && data_in == 8'd0)) h_commit <= 1'b1;
                end
              end

        8'd5: if(cnt == 12'd0) begin
                plip_en <= data_in[0];
                plip_loop <= data_in[1];
              end

`ifdef PLIP_LITE
        8'd6: data_out <= 8'h00;                 // keine Statistik
`else
        8'd6: data_out <= (cnt == 12'd0) ? 8'h00 :
                          (cnt <= 12'd12) ? stats[(12 - cnt) * 8 +: 8] : 8'h00;
`endif

        default: data_out <= 8'h00;
      endcase
    end
  end
end

endmodule
