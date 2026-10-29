/*
    uart_port.v

    Bridge between the serial port of the Amiga (paula_uart, bit level)
    and the "port" interface of the FPGA Companion (byte level, see
    sysctrl.v command 7). The companion offers a virtual Hayes/AT modem
    on that port, exactly as it does for the MFP of the MiSTeryNano.

    The bit timing is derived from the SERPER register of paula, so
    the bridge follows whatever baud rate the Amiga software selects.
    Frames are 8N1.

    amiga -> mcu: txd of paula is sampled and complete bytes are pushed
                  into a fifo. While that fifo is full the transmitter of
                  paula is held back (hold), so no data is lost.
    mcu -> amiga: bytes from the mcu fifo are sent as frames to rxd of
                  paula. The next byte is not sent before the previous
                  one has been read by the Amiga (rbf cleared), so
                  the receiver never overruns.
*/

module uart_port #(
  // both fifos hold 2**FIFO_BITS-1 bytes (original: 4 = 15 bytes, which is only 1.3 ms at 115200 Bd)
  parameter FIFO_BITS = 6
) (
  input             clk,        // 28 MHz system clock
  input             clk7_en,    // 7 MHz enable, bit times are counted in these
  input             reset,

  // paula side
  input [14:0]      serper,     // SERPER, bit time is 2*serper+2 clk7 cycles
  input             rbf,        // receive buffer full (intreq[11])
  input             txd,        // serial data from paula
  output            rxd,        // serial data to paula
  output            hold,       // tx fifo is full, paula must not start a frame

  // mcu side (same names as in MiSTeryNano atarist.v)
  output [31:0]     serial_status,
  output [7:0]      serial_tx_available,  // bytes waiting for the mcu
  input             serial_tx_strobe,
  output [7:0]      serial_tx_data,
  output [7:0]      serial_rx_available,  // free bytes in fifo to paula
  input             serial_rx_strobe,
  input [7:0]       serial_rx_data
);

// ------------------------------------------------------------------
// amiga -> mcu
// ------------------------------------------------------------------

wire       tx_full;
reg        tx_push;
reg  [7:0] tx_byte;

assign hold = tx_full;
wire [FIFO_BITS-1:0] tx_used;
assign serial_tx_available = { {(8-FIFO_BITS){1'b0}}, tx_used };

io_fifo #(.DEPTH(FIFO_BITS)) tx_fifo (
  .reset      ( reset ),

  .in_clk     ( clk ),
  .in         ( tx_byte ),
  .in_strobe  ( 1'b0 ),
  .in_enable  ( tx_push ),

  .out_clk    ( clk ),
  .out        ( serial_tx_data ),
  .out_strobe ( serial_tx_strobe ),
  .out_enable ( 1'b0 ),

  .space      (  ),
  .used       ( tx_used ),
  .empty      (  ),
  .full       ( tx_full )
);

localparam [1:0] TX_IDLE = 2'd0, TX_START = 2'd1, TX_DATA = 2'd2, TX_STOP = 2'd3;
reg [1:0]  tx_state;
reg [15:0] tx_cnt;
reg [2:0]  tx_bit;
reg        txd_d;

always @(posedge clk) begin
  tx_push <= 1'b0;

  if(reset) begin
    tx_state <= TX_IDLE;
    txd_d <= 1'b1;
  end else if(clk7_en) begin
    txd_d <= txd;

    case(tx_state)
      TX_IDLE:    // wait for falling edge of the start bit
        if(txd_d && !txd) begin
          tx_cnt <= { 1'b0, serper };       // half a bit: sample in the middle
          tx_state <= TX_START;
        end

      TX_START:
        if(tx_cnt == 16'd0) begin
          if(!txd) begin                    // start bit still valid
            tx_cnt <= { serper, 1'b1 };
            tx_bit <= 3'd0;
            tx_state <= TX_DATA;
          end else
            tx_state <= TX_IDLE;            // glitch
        end else
          tx_cnt <= tx_cnt - 16'd1;

      TX_DATA:
        if(tx_cnt == 16'd0) begin
          tx_byte <= { txd, tx_byte[7:1] }; // lsb first
          tx_cnt <= { serper, 1'b1 };
          tx_bit <= tx_bit + 3'd1;
          if(tx_bit == 3'd7) tx_state <= TX_STOP;
        end else
          tx_cnt <= tx_cnt - 16'd1;

      TX_STOP:
        if(tx_cnt == 16'd0) begin
          // a low stop bit is a framing error or break: drop the byte
          if(txd && !tx_full) tx_push <= 1'b1;
          tx_state <= TX_IDLE;
        end else
          tx_cnt <= tx_cnt - 16'd1;
    endcase
  end
end

// ------------------------------------------------------------------
// mcu -> amiga
// ------------------------------------------------------------------

wire [7:0] rx_byte;
wire       rx_empty;
reg        rx_pop;

wire [FIFO_BITS-1:0] rx_space;
assign serial_rx_available = { {(8-FIFO_BITS){1'b0}}, rx_space };

io_fifo #(.DEPTH(FIFO_BITS)) rx_fifo (
  .reset      ( reset ),

  .in_clk     ( clk ),
  .in         ( serial_rx_data ),
  .in_strobe  ( serial_rx_strobe ),
  .in_enable  ( 1'b0 ),

  .out_clk    ( clk ),
  .out        ( rx_byte ),
  .out_strobe ( 1'b0 ),
  .out_enable ( rx_pop ),

  .space      ( rx_space ),
  .empty      ( rx_empty ),
  .full       (  )
);

reg [9:0]  rx_sr = 10'h3ff;   // stop, 8 data bits, start (lsb first out)
reg [3:0]  rx_bits;
reg [15:0] rx_cnt;
reg        rx_busy;

assign rxd = rx_sr[0];

// don't start while the baud rate is unset (serper == 0)
wire rx_start = !rx_busy && !rx_empty && (serper != 15'd0) && !rbf;

always @(posedge clk) begin
  rx_pop <= 1'b0;

  if(reset) begin
    rx_sr <= 10'h3ff;
    rx_busy <= 1'b0;
  end else if(clk7_en) begin
    if(rx_start) begin
      rx_sr <= { 1'b1, rx_byte, 1'b0 };
      rx_bits <= 4'd10;
      rx_cnt <= { serper, 1'b1 };
      rx_busy <= 1'b1;
      rx_pop <= 1'b1;
    end else if(rx_busy) begin
      if(rx_cnt == 16'd0) begin
        rx_sr <= { 1'b1, rx_sr[9:1] };
        rx_cnt <= { serper, 1'b1 };
        rx_bits <= rx_bits - 4'd1;
        if(rx_bits == 4'd1) rx_busy <= 1'b0;
      end else
        rx_cnt <= rx_cnt - 16'd1;
    end
  end
end

// bit rate is not reported (0x800001 = "unsupported" as in the MiSTeryNano mfp),
// the frame format is fixed to 8N1
wire [23:0] bitrate = 24'h800001;
assign serial_status = { bitrate[7:0], bitrate[15:8], bitrate[23:16],
                         4'd8, 2'd0, 2'd0 };

endmodule
