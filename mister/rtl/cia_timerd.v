// CIA Timer D - Time of Day (TOD) Clock Module
// Implements Time of Day (TOD) functionality for Amiga CIA chip
// Note: TOD is implemented as binary counter (Amiga style), not BCD (C64 style)
// Counts external pulses (typically 50/60 Hz from power line frequency)
// Includes alarm functionality for time-based interrupts
module cia_timerd
(
  input   clk,            // System clock
  input clk7_en,          // 7MHz clock enable for synchronization
  input  wr,              // Write enable signal
  input   reset,          // Synchronous reset

  // Register select signals from address decoder
  input   tlo,            // Timer low byte select (bits 7:0)
  input   tme,            // Timer mid byte select (bits 15:8)
  input  thi,             // Timer high byte select (bits 23:16)
  input  tcr,             // Timer control register select

  input   [7:0] data_in,  // CPU data bus input
  output   reg [7:0] data_out, // CPU data bus output
  input  count,           // Count enable (typically 50/60 Hz tick)
  output  irq             // Alarm interrupt request
);

  // Internal registers
  reg    latch_ena;       // TOD output latch control
  reg   count_ena;        // TOD counting enable
  reg    crb7;            // CRB bit 7: TOD/ALARM register select
  reg    [23:0] tod;      // 24-bit TOD counter (binary, not BCD)
  reg    [23:0] alarm;    // 24-bit alarm compare value
  reg    [23:0] tod_latch; // TOD readout latch (for consistent multi-byte reads)
  reg    count_del;       // Delayed count signal for edge detection
  reg    count_del2;      // Double delayed count signal for interrupt generation

// TOD Read Latching Mechanism:
// Reading TOD registers must be done in specific order to ensure consistency
// - Reading high byte (minutes) latches entire TOD value
// - Subsequent reads of middle/low bytes return latched values
// - Reading low byte releases the latch for next update
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      latch_ena <= 1'd1;  // Latch enabled after reset
    else if (!wr)
    begin
      if (thi && !crb7)    // if MSB read and ALARM is not selected, hold data for subsequent reads
        latch_ena <= 1'd0; // Freeze latch to ensure consistent read
      else if (tlo)        // if LSB read, update data every clock
        latch_ena <= 1'd1; // Release latch for updates
    end
  end

// TOD latch update
// Captures current TOD value when latch is enabled
always @(posedge clk)
  if (clk7_en) begin
    if (latch_ena)
      tod_latch[23:0] <= tod[23:0];
  end

// CPU Read Data Multiplexer
// CRB bit 7 = 0: Read TOD registers
// CRB bit 7 = 1: Read ALARM registers (write-only, reads as TOD)
always @(*)
  if (!wr)
  begin
    if (thi)      // High byte of timer D
      data_out[7:0] = tod_latch[23:16];
    else if (tme) // Middle byte of timer D (latched)
      data_out[7:0] = tod_latch[15:8];
    else if (tlo) // Low byte of timer D (latched)
      data_out[7:0] = tod_latch[7:0];
    else if (tcr) // Control register B bit 7 only
      data_out[7:0] = {crb7,7'b000_0000};
    else
      data_out[7:0] = 8'd0;
  end
  else
    data_out[7:0] = 8'd0;

// TOD Write Control:
// Writing to high byte stops TOD counting
// Writing to low byte starts TOD counting again
// This ensures consistent time setting
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      count_ena <= 1'd1;  // Counting enabled after reset
    else if (wr && !crb7) // crb7==0 enables writing to TOD counter
    begin
      if (thi/* || tme*/) // Stop counting during update
        count_ena <= 1'd0;
      else if (tlo)       // write to LSB starts counting again
        count_ena <= 1'd1;
    end
  end

// TOD Counter
// Note: counts in binary, not BCD
// Emulates buggy TOD behavior where carry from lower 12 bits
// is delayed by one cycle when updating upper 12 bits
reg todcarry; // Carry flag for delayed upper counter update
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
    begin
      tod[23:0] <= 24'd0;  // Clear counter on reset
    end
    else if (wr && !crb7)  // CRB7==0 enables writing to TOD counter
    begin
      if (tlo)
        tod[7:0] <= data_in[7:0];
      if (tme)
        tod[15:8] <= data_in[7:0];
      if (thi)
        tod[23:16] <= data_in[7:0];
    end
    else if (count_ena && count) begin
		todcarry <= &tod[11:0];
      tod[11:0] <= tod[11:0] + 12'd1;
    end
	 else if (count_ena && count_del)
	   tod[23:12] <= tod[23:12] + todcarry;

  end

// ALARM Register Write
// Written when CRB bit 7 = 1
always @(posedge clk)
  if (clk7_en) begin
    if (reset) // synchronous reset
    begin
      // Set alarm to maximum value (never match by default)
      alarm[7:0] <= 8'b1111_1111;
      alarm[15:8] <= 8'b1111_1111;
      alarm[23:16] <= 8'b1111_1111;
    end
    else if (wr && crb7)  // CRB7=1 enables writing to ALARM
    begin
      if (tlo)
        alarm[7:0] <= data_in[7:0];
      if (tme)
        alarm[15:8] <= data_in[7:0];
      if (thi)
        alarm[23:16] <= data_in[7:0];
    end
  end

// Control Register B bit 7
// Selects between TOD and ALARM for read/write operations
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      crb7 <= 1'd0;  // Default to TOD access
    else if (wr && tcr)
      crb7 <= data_in[7];
  end

// delayed count enable signal
always @(posedge clk)
  if (clk7_en) begin
    count_del <= count & count_ena;
    count_del2 <= count_del & count_ena;
  end

// alarm interrupt request
assign irq = (tod[23:0]==alarm[23:0] && (count_del || count_del2)) ? 1'b1 : 1'b0;


endmodule