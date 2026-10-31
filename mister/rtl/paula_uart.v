/* uart */


module paula_uart (
  input  wire           clk,
  input  wire           clk7_en,
  input  wire           reset,
  input  wire [  8-1:0] rga_i,
  input  wire [ 16-1:0] data_i,
  output wire [ 16-1:0] data_o,
  input  wire           uartbrk,
  input  wire           rbfmirror,
  output wire           txint,
  output wire           rxint,
  output wire           txd,
  input  wire           rxd
);


//// registers ////
localparam REG_SERDAT  = 9'h030;
localparam REG_SERDATR = 9'h018;
localparam REG_SERPER  = 9'h032;


//// bits ////
localparam LONG_BIT  = 15;
localparam OVRUN_BIT = 15-11;
localparam RBF_BIT   = 14-11;
localparam TBE_BIT   = 13-11;
localparam TSRE_BIT  = 12-11;
localparam RXD_BIT   = 11-11;


//// RX input sync ////
reg  [  2-1:0] rxd_sync = 2'b11;
wire           rxds;
always @ (posedge clk) begin
  if (clk7_en) begin
    rxd_sync <= #1 {rxd_sync[0],rxd};
  end
end
assign rxds = rxd_sync[1];


//// write registers ////

// SERPER
reg  [ 16-1:0] serper = 16'h0000;
always @ (posedge clk) begin
  if (clk7_en) begin
    if (rga_i == REG_SERPER[8:1])
      serper <= #1 data_i;
  end
end

// SERDAT
reg  [ 16-1:0] serdat = 16'h0000;
always @ (posedge clk) begin
  if (clk7_en) begin
    if (rga_i == REG_SERDAT[8:1])
      serdat <= #1 data_i;
  end
end


//// TX ////
localparam [  2-1:0] TX_IDLE=2'd0, TX_SHIFT=2'd2;
reg  [  2-1:0] tx_state;
reg  [ 16-1:0] tx_cnt;
reg  [ 16-1:0] tx_shift;
reg            tx_txd;
reg            tx_irq;
reg            tx_tbe;
reg            tx_tsre;

always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset) begin
      tx_state  <= #1 TX_IDLE;
      tx_txd    <= #1 1'b1;
      tx_irq    <= #1 1'b0;
      tx_tbe    <= #1 1'b1;
      tx_tsre   <= #1 1'b1;
    end else begin
      case (tx_state)
        TX_IDLE : begin
          // txd pin inactive in idle state
          tx_txd <= #1 1'b1;
          // check if new data loaded to serdat register
          if (!tx_tbe) begin
            // set interrupt request
            tx_irq <= #1 1'b1;
            // data buffer empty again
            //tx_tbe <= #1 1'b1;
            // generate start bit
            tx_txd <= #1 1'b0;
            // pass data to a shift register
            tx_tsre <= #1 1'b0;
            tx_shift <= #1 serdat;
            // reload period register
            tx_cnt <= #1 {serper[14:0], 1'b1};
            // start bitstream generation
            tx_state <= #1 TX_SHIFT;
          end
        end
        TX_SHIFT: begin
          // clear interrupt request, active by 1 cycle of clk
          tx_irq <= #1 1'b0;
          // count bit period
          if (tx_cnt == 16'd0) begin
            // check if any bit left to send out
            if (tx_shift == 16'd0) begin
              // set TSRE flag when serdat register is empty
              if (tx_tbe) tx_tsre <= #1 1'b1;
              // data sent, go to idle state
              tx_state <= #1 TX_IDLE;
            end else begin
              // reload period counter
              tx_cnt <= #1 {serper[14:0], 1'b1};
              // update shift register and txd pin
              tx_shift <= #1 {1'b0, tx_shift[15:1]};
              tx_txd <= #1 tx_shift[0];
            end
          end else begin
            // decrement period counter
            tx_cnt <= #1 tx_cnt - 16'd1;
          end
        end
        default: begin
          // force idle state
          tx_state <= #1 TX_IDLE;
        end
      endcase
      // force break char when requested
      if (uartbrk) tx_txd <= #1 1'b0;
      // handle tbe bit
      //if (rga_i == REG_SERDAT[8:1]) tx_tbe <= #1 1'b0;
      tx_tbe <= #1 (rga_i == REG_SERDAT[8:1]) ? 1'b0 : ((tx_state == TX_IDLE) ? 1'b1 : tx_tbe);
    end
  end
end


//// RX ////
localparam [  2-1:0] RX_IDLE=2'd0, RX_START=2'd1, RX_SHIFT=2'd2;
reg  [  2-1:0] rx_state;
reg  [ 16-1:0] rx_cnt;
reg  [ 10-1:0] rx_shift;
reg  [ 10-1:0] rx_data;
reg            rx_rbf;
reg            rx_rxd;
reg            rx_irq;
reg            rx_ovrun;

always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset) begin
      rx_state <= #1 RX_IDLE;
      rx_rbf   <= #1 1'b0;
      rx_rxd   <= #1 1'b1;
      rx_irq   <= #1 1'b0;
      rx_ovrun <= #1 1'b0;
    end else begin
      case (rx_state)
        RX_IDLE : begin
          // clear interrupt request
          rx_irq <= #1 1'b0;
          // wait for start condition
          if (rx_rxd && !rxds) begin
            // setup received data format
            rx_shift <= #1 {serper[LONG_BIT], {9{1'b1}}};
            rx_cnt <= #1 {1'b0, serper[14:0]};
            // wait for a sampling point of a start bit
            rx_state <= #1 RX_START;
          end
        end
        RX_START : begin
          // wait for a sampling point
          if (rx_cnt == 16'h0) begin
            // sample rxd signal
            if (!rxds) begin
              // start bit valid, start data shifting
              rx_shift <= #1 {rxds, rx_shift[9:1]};
              // restart period counter
              rx_cnt <= #1 {serper[14:0], 1'b1};
              // start data bits sampling
              rx_state <= #1 RX_SHIFT;
            end else begin
              // start bit invalid, return into idle state
              rx_state <= #1 RX_IDLE;
            end
          end else begin
            rx_cnt <= #1 rx_cnt - 16'd1;
          end
          // check false start condition
          if (!rx_rxd && rxds) begin
            rx_state <= #1 RX_IDLE;
          end
        end
        RX_SHIFT : begin
          // wait for bit period
          if (rx_cnt == 16'h0) begin
            // store received bit
            rx_shift <= #1 {rxds, rx_shift[9:1]};
            // restart period counter
            rx_cnt <= #1 {serper[14:0], 1'b1};
            // check for all bits received
            if (rx_shift[0] == 1'b0) begin
              // set interrupt request flag
              rx_irq <= #1 1'b1;
              // handle OVRUN bit
              //rx_ovrun <= #1 rbfmirror;
              // update receive buffer
              rx_data[9] <= #1 rxds;
              if (serper[LONG_BIT]) begin
                rx_data[8:0] <= #1 rx_shift[9:1];
              end else begin
                rx_data[8:0] <= #1 {rxds, rx_shift[9:2]};
              end
              // go to idle state
              rx_state <= #1 RX_IDLE;
            end
          end else begin
            rx_cnt <= #1 rx_cnt - 16'd1;
          end
        end
        default : begin
          // force idle state
          rx_state <= #1 RX_IDLE;
        end
      endcase
      // register rxds
      rx_rxd <= #1 rxds;
      // handle ovrun bit
      rx_rbf <= #1 rbfmirror;
      //if (!rbfmirror &&  rx_rbf) rx_ovrun <= #1 1'b0;
      rx_ovrun <= #1 (!rbfmirror &&  rx_rbf) ? 1'b0 : (((rx_state == RX_SHIFT) && ~|rx_cnt && !rx_shift[0]) ? rbfmirror : rx_ovrun);
    end
  end
end


//// outputs ////

// SERDATR
wire [  5-1:0] serdatr;
assign serdatr  = {rx_ovrun, rx_rbf, tx_tbe, tx_tsre, rx_rxd};

// interrupts
assign txint = tx_irq;
assign rxint = rx_irq;

// uart output
assign txd   = tx_txd;

// reg bus output
assign data_o = (rga_i == REG_SERDATR[8:1]) ? {serdatr, 1'b0, rx_data} : 16'h0000;


endmodule

