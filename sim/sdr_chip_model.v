// sdr_chip_model.v
//
// Behavioral model of the Tang Nano 20K's in-package 32 bit SDR SDRAM,
// just detailed enough for the NanoMig sdram.sv controller: ACTIVE/READ/
// WRITE/LOAD MODE with CAS latency 2, burst length 1 or 2 (sequential,
// wrapping within the aligned pair), byte masks on writes, single writes
// (write burst disabled). Refresh and precharge are accepted and ignored.
//
// The memory array is verilator-public so the testbench can preload the
// kickstart image directly.

module sdr_chip_model (
   input	 clk,     // controller/SDRAM clock (85MHz)
   inout [31:0]	 dq,
   input [10:0]	 addr,
   input [3:0]	 dqm,
   input [1:0]	 ba,
   input	 cs_n,
   input	 ras_n,
   input	 cas_n,
   input	 we_n
);

/* verilator no_inline_module */

// 8MB as 2M x 32
reg [31:0] mem [0:2097151] /*verilator public_flat_rw*/;

reg [10:0] row [0:3];
reg	   burst2;         // mode register burst length 2

wire [2:0] command = {ras_n, cas_n, we_n};
localparam CMD_ACTIVE    = 3'b011;
localparam CMD_READ      = 3'b101;
localparam CMD_WRITE     = 3'b100;
localparam CMD_LOAD_MODE = 3'b000;

// read data pipeline for CAS latency 2
reg	    v0, v1;
reg [31:0]  d0, d1;
reg	    pend;         // second beat of a burst-2 read pending
reg [20:0]  pa;           // address of the first beat

wire [20:0] col_addr = {ba, row[ba], addr[7:0]};

always @(posedge clk) begin
   // advance the CL pipeline
   v1 <= v0;
   d1 <= d0;
   v0 <= 1'b0;

   if (pend) begin
      // sequential burst-2 wraps within the aligned pair
      d0   <= mem[{pa[20:1], ~pa[0]}];
      v0   <= 1'b1;
      pend <= 1'b0;
   end

   if (!cs_n) begin
      case (command)
	CMD_LOAD_MODE: burst2 <= (addr[2:0] == 3'b001);
	CMD_ACTIVE:    row[ba] <= addr;
	CMD_READ: begin
	   d0   <= mem[col_addr];
	   v0   <= 1'b1;
	   pa   <= col_addr;
	   pend <= burst2;
	end
	CMD_WRITE: begin
	   // single write with byte masks (write burst disabled)
	   if (!dqm[3]) mem[col_addr][31:24] <= dq[31:24];
	   if (!dqm[2]) mem[col_addr][23:16] <= dq[23:16];
	   if (!dqm[1]) mem[col_addr][15: 8] <= dq[15: 8];
	   if (!dqm[0]) mem[col_addr][ 7: 0] <= dq[ 7: 0];
	   pend <= 1'b0;
	end
	default: ;  // nop/refresh/precharge ignored
      endcase
   end
end

assign dq = v1 ? d1 : 32'hzzzzzzzz;

endmodule
