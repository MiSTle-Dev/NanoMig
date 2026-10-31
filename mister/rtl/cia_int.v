// CIA Interrupt Controller Module
// This module manages interrupt generation and masking for the CIA chip
// It handles 5 interrupt sources: Timer A, Timer B, Alarm (TOD), Serial Port, and FLAG input
module cia_int
(
  input   clk,          // System clock
  input clk7_en,        // 7MHz clock enable signal for synchronization
  input  wr,            // Write enable signal (active high)
  input   reset,        // Synchronous reset signal
  input   icrs,         // Interrupt Control Register Select - enables access to ICR

  // Interrupt source inputs
  input  ta,            // Timer A underflow interrupt request
  input  tb,            // Timer B underflow interrupt request
  input  alrm,          // Time-of-Day (TOD) alarm match interrupt request
  input   flag,         // External FLAG pin interrupt request (e.g., disk index)
  input   ser,          // Serial port interrupt request (keyboard/transmit complete)

  input   [7:0] data_in,    // CPU data bus input
  output   [7:0] data_out,   // CPU data bus output
  output  irq               // Combined interrupt request output to CPU
);

// ICR - Interrupt Control Register (Read: status, Write: mask control)
// Bit 7: IR - Interrupt Request (any enabled interrupt occurred) [Read only]
// Bit 6-5: Unused, always read as 0
// Bit 4: FLG - FLAG pin interrupt occurred/enabled
// Bit 3: SP - Serial Port interrupt occurred/enabled
// Bit 2: ALRM - TOD Alarm interrupt occurred/enabled
// Bit 1: TB - Timer B interrupt occurred/enabled
// Bit 0: TA - Timer A interrupt occurred/enabled
reg  [4:0] icr = 5'd0;      // Interrupt status register (latched interrupt flags)
reg  [4:0] icrmask = 5'd0;  // Interrupt mask register (which interrupts are enabled)

// Reading ICR returns interrupt status
// Bit 7 shows if any enabled interrupt is pending (irq signal state)
// Bits 4:0 show which interrupt sources have triggered
// Reading ICR clears all interrupt flags
assign data_out[7:0] = icrs && !wr ? {irq,2'b00,icr[4:0]} : 8'b0000_0000;

// Writing to ICR modifies the interrupt mask
// Bit 7 = 1: Set mask bits (enable interrupts)
// Bit 7 = 0: Clear mask bits (disable interrupts)
// Only bits specified as 1 in data_in[4:0] are affected
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      icrmask[4:0] <= 5'b0_0000;  // All interrupts disabled on reset
    else if (icrs && wr)
    begin
      if (data_in[7])  // Set/Clear control bit
        icrmask[4:0] <= icrmask[4:0] | data_in[4:0];  // Set mask bits
      else
        icrmask[4:0] <= icrmask[4:0] & (~data_in[4:0]); // Clear mask bits
    end
  end

// Interrupt flag latching logic
// Flags remain set until ICR is read
// New interrupts can be latched even while previous ones are pending
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      icr[4:0] <= 5'b0_0000;  // Clear all interrupt flags
    else if (icrs && !wr)     // Reading ICR
    begin
      // Clear all flags and capture any new interrupts occurring this cycle
      icr[0] <= ta;      // Timer A underflow
      icr[1] <= tb;      // Timer B underflow
      icr[2] <= alrm;    // TOD alarm match
      icr[3] <= ser;     // Serial port (keyboard data or transmit complete)
      icr[4] <= flag;    // External FLAG pin
    end
    else
    begin
      // Latch new interrupts (OR with existing flags)
      icr[0] <= icr[0] | ta;
      icr[1] <= icr[1] | tb;
      icr[2] <= icr[2] | alrm;
      icr[3] <= icr[3] | ser;
      icr[4] <= icr[4] | flag;
    end
  end

// Generate IRQ output
// IRQ is asserted when any enabled interrupt flag is set
// This is a combinational output for immediate interrupt response
assign irq   = (icrmask[0] & icr[0])    // Timer A interrupt enabled and pending
      | (icrmask[1] & icr[1])          // Timer B interrupt enabled and pending
      | (icrmask[2] & icr[2])          // Alarm interrupt enabled and pending
      | (icrmask[3] & icr[3])          // Serial interrupt enabled and pending
      | (icrmask[4] & icr[4]);         // FLAG interrupt enabled and pending


endmodule