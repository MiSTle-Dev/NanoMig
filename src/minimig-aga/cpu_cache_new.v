// cpu_cache_new.v
// 2015, rok.krajnc@gmail.com
// this is a 2-way set-associative cache
// seperate instruction and data caches
// write-through, look-through
// 4kB cache size, 2kB per way
// whole cache size (I+D) is 8kB
//
// ----------------------------------------------------
//
// - ChipRAM/ROM fixes
// - Support up to 256MB address space
//               (C) 2019 Alexey Melnikov
//
//

module cpu_cache_new
(
  // system
  input             clk,            // clock
  input             rst,            // cache reset
  input       [3:0] cpu_cache_ctrl, // CPU cache control
  input             cache_inhibit,  // cache inhibit

  // cpu    
  input             cpu_cs,         // cpu activity
  input      [28:1] cpu_adr,        // cpu address
  input       [1:0] cpu_bs,         // cpu byte selects
  input             cpu_we,         // cpu write
  input             cpu_ir,         // cpu instruction read
  input             cpu_dr,         // cpu data read
  input      [15:0] cpu_dat_w,      // cpu write data
  output reg [15:0] cpu_dat_r,      // cpu read data
  output reg        cpu_ack,        // cpu acknowledge

  // writebuffer
  output reg        wb_en,          // writebuffer enable

  // sdram
  input      [15:0] sdr_dat_r,      // sdram read data
  output reg        sdr_read_req,   // sdram read request from cache
  input             sdr_read_ack,   // sdram read acknowledge to cache

  // snoop
  input             snoop_act,      // snoop act (write only - just update existing data in cache)
  input      [28:1] snoop_adr,      // chip address                      
  input      [15:0] snoop_dat_w,    // snoop write data
  input       [1:0] snoop_bs
);


//// internal signals ////

// cache init
reg           cache_init_done;
// state
reg   [3:0] cpu_sm_state;
reg   [3:0] sdr_sm_state;
// state signals
reg         fill;
reg   [9:0] cpu_sm_adr;
reg         cpu_sm_itag_we;
reg         cpu_sm_dtag_we;
reg         cpu_sm_iram0_we;
reg         cpu_sm_iram1_we;
reg         cpu_sm_dram0_we;
reg         cpu_sm_dram1_we;
reg   [1:0] cpu_sm_bs;
reg  [15:0] cpu_sm_mem_dat_w;
reg  [39:0] cpu_sm_tag_dat_w;
reg         cpu_sm_id;
reg         cpu_sm_ilru;
reg         cpu_sm_dlru;
reg   [9:0] sdr_sm_adr;
reg         sdr_sm_itag_we;
reg         sdr_sm_dtag_we;
reg         sdr_sm_iram0_we;
reg         sdr_sm_iram1_we;
reg         sdr_sm_dram0_we;
reg         sdr_sm_dram1_we;
reg  [15:0] sdr_sm_mem_dat_w;
reg  [39:0] sdr_sm_tag_dat_w;
reg         sdr_sm_id;
reg         sdr_sm_ilru;
reg         sdr_sm_dlru;

// cpu cache control
reg   [1:0] cc_clr_r;
wire        cpu_cache_enable;
wire        cpu_cache_clear;
reg         cc_en;
reg         cc_clr;
// cpu address
wire  [1:0] cpu_adr_blk;
wire  [7:0] cpu_adr_idx;
wire [17:0] cpu_adr_tag;
// idram0
wire  [9:0] idram0_cpu_adr;
wire  [1:0] idram0_cpu_bs;
wire        idram0_cpu_we;
wire [15:0] idram0_cpu_dat_w;
wire [15:0] idram0_cpu_dat_r;
wire  [9:0] idram0_sdr_adr;
wire  [1:0] idram0_sdr_bs;
wire        idram0_sdr_we;
wire [15:0] idram0_sdr_dat_w;
wire [15:0] idram0_sdr_dat_r;
// idram1
wire  [9:0] idram1_cpu_adr;
wire  [1:0] idram1_cpu_bs;
wire        idram1_cpu_we;
wire [15:0] idram1_cpu_dat_w;
wire [15:0] idram1_cpu_dat_r;
wire  [9:0] idram1_sdr_adr;
wire  [1:0] idram1_sdr_bs;
wire        idram1_sdr_we;
wire [15:0] idram1_sdr_dat_w;
wire [15:0] idram1_sdr_dat_r;
// ddram0
wire  [9:0] ddram0_cpu_adr;
wire  [1:0] ddram0_cpu_bs;
wire        ddram0_cpu_we;
wire [15:0] ddram0_cpu_dat_w;
wire [15:0] ddram0_cpu_dat_r;
wire  [9:0] ddram0_sdr_adr;
wire  [1:0] ddram0_sdr_bs;
wire        ddram0_sdr_we;
wire [15:0] ddram0_sdr_dat_w;
wire [15:0] ddram0_sdr_dat_r;
// ddram1
wire  [9:0] ddram1_cpu_adr;
wire  [1:0] ddram1_cpu_bs;
wire        ddram1_cpu_we;
wire [15:0] ddram1_cpu_dat_w;
wire [15:0] ddram1_cpu_dat_r;
wire  [9:0] ddram1_sdr_adr;
wire  [1:0] ddram1_sdr_bs;
wire        ddram1_sdr_we;
wire [15:0] ddram1_sdr_dat_w;
wire [15:0] ddram1_sdr_dat_r;
// itram
wire  [7:0] itram_cpu_adr;
wire        itram_cpu_we;
wire [39:0] itram_cpu_dat_w;
wire [39:0] itram_cpu_dat_r;
wire  [7:0] itram_sdr_adr;
wire        itram_sdr_we;
wire [39:0] itram_sdr_dat_w;
wire [39:0] itram_sdr_dat_r;
wire        itag0_match;
wire        itag1_match;
wire        itag_lru;
wire        itag0_valid;
wire        itag1_valid;
wire        sdr_itag0_match;
wire        sdr_itag1_match;
wire        sdr_itag0_valid;
wire        sdr_itag1_valid;
// dtram
wire  [7:0] dtram_cpu_adr;
wire        dtram_cpu_we;
wire [39:0] dtram_cpu_dat_w;
wire [39:0] dtram_cpu_dat_r;
wire  [7:0] dtram_sdr_adr;
wire        dtram_sdr_we;
wire [39:0] dtram_sdr_dat_w;
wire [39:0] dtram_sdr_dat_r;
wire        dtag0_match;
wire        dtag1_match;
wire        dtag_lru;
wire        dtag0_valid;
wire        dtag1_valid;
wire        sdr_dtag0_match;
wire        sdr_dtag1_match;
wire        sdr_dtag0_valid;
wire        sdr_dtag1_valid;


//// params ////

// cpu-side state machine
localparam [3:0]
	CPU_SM_INIT  = 4'd0,
	CPU_SM_IDLE  = 4'd1,
	CPU_SM_WRITE = 4'd2,
	CPU_SM_WB    = 4'd3,
	CPU_SM_READ  = 4'd4,
	CPU_SM_WAIT  = 4'd5,
	CPU_SM_FILL1 = 4'd6,
	CPU_SM_FILL2 = 4'd7,
	CPU_SM_FILL3 = 4'd8,
	CPU_SM_FILL4 = 4'd9,
	CPU_SM_FILLW = 4'd10;

// sdram-side state machine
localparam [3:0]
	SDR_SM_INIT0 = 4'd0,
	SDR_SM_INIT1 = 4'd1,
	SDR_SM_IDLE  = 4'd2,
	SDR_SM_SNOOP = 4'd3,
	SDR_SM_FILL  = 4'd4,
	SDR_SM_FILL1 = 4'd5,
	SDR_SM_FILL2 = 4'd6,
	SDR_SM_FILL3 = 4'd7,
	SDR_SM_WAIT  = 4'd8;


//// cpu side ////

// cpu cache control
always @ (posedge clk) begin
	if (rst) cc_clr_r <= 2'd0;
	else if (!cpu_cs) cc_clr_r <= {cc_clr_r[0], cpu_cache_ctrl[3]};
end

assign cpu_cache_enable = cpu_cache_ctrl[0];
//assign cpu_cache_freeze = cpu_cache_ctrl[1];
assign cpu_cache_clear  = cc_clr_r[0] && !cc_clr_r[1];

always @ (posedge clk) begin
	if (rst) begin
		cc_en  <= 1'b0;
		//cc_fr  <= 1'b0;
		cc_clr <= 1'b0;
	end else if (!cpu_cs) begin
		cc_en  <= cpu_cache_enable;
		//cc_fr  <= cpu_cache_freeze;
		cc_clr <= cpu_cache_clear;
	end
end 

// slice up cpu address
assign cpu_adr_blk = cpu_adr[2:1];    // cache block address (inside cache row), 2 bits for 4x16 rows
assign cpu_adr_idx = cpu_adr[10:3];   // cache row address, 8 bits
assign cpu_adr_tag = cpu_adr[28:11];  // tag, 18 bits

// cpu side state machine
always @ (posedge clk) begin
  if (rst) begin
    fill              <= 1'b0;
    sdr_read_req      <= 1'b0;
    wb_en             <= 1'b0;
    cpu_ack           <= 1'b0;
    cpu_sm_state      <= CPU_SM_INIT;
    cpu_sm_itag_we    <= 1'b0;
    cpu_sm_dtag_we    <= 1'b0;
    cpu_sm_iram0_we   <= 1'b0;
    cpu_sm_iram1_we   <= 1'b0;
    cpu_sm_dram0_we   <= 1'b0;
    cpu_sm_dram1_we   <= 1'b0;
    cpu_sm_bs         <= 2'b11;
  end else begin
    // default values
    fill              <= 1'b0;
    sdr_read_req      <= 1'b0;
    wb_en             <= 1'b0;
    cpu_sm_itag_we    <= 1'b0;
    cpu_sm_dtag_we    <= 1'b0;
    cpu_sm_iram0_we   <= 1'b0;
    cpu_sm_iram1_we   <= 1'b0;
    cpu_sm_dram0_we   <= 1'b0;
    cpu_sm_dram1_we   <= 1'b0;
    cpu_sm_bs         <= 2'b11;
    // state machine
    case (cpu_sm_state)
      CPU_SM_INIT : begin
        // waiting for cache init
        if (cache_init_done) begin
          cpu_sm_state <= CPU_SM_IDLE;
        end else begin
          cpu_sm_state <= CPU_SM_INIT;
        end
      end
      CPU_SM_IDLE : begin
        // waiting for CPU access
        if (cpu_cs) begin
          if (cpu_we) begin
            cpu_sm_state <= CPU_SM_WRITE;
          end else begin
            cpu_sm_state <= CPU_SM_READ;
          end
        end else begin
          if (cc_clr)
            cpu_sm_state <= CPU_SM_INIT;
          else
            cpu_sm_state <= CPU_SM_IDLE;
        end
      end
      CPU_SM_WRITE : begin
        // on hit update cache, on miss no update neccessary; tags don't get updated on writes
        cpu_sm_bs <= cpu_bs;
        cpu_sm_mem_dat_w <= cpu_dat_w;
        cpu_sm_iram0_we <= itag0_match && itag0_valid /*&& !cc_fr*/;
        cpu_sm_iram1_we <= itag1_match && itag1_valid /*&& !cc_fr*/;
        cpu_sm_dram0_we <= dtag0_match && dtag0_valid /*&& !cc_fr*/;
        cpu_sm_dram1_we <= dtag1_match && dtag1_valid /*&& !cc_fr*/;
        cpu_sm_state <= CPU_SM_WB;
        wb_en <= 1'b1;
        if (!cpu_cs) cpu_sm_state <= CPU_SM_IDLE;
      end
      CPU_SM_WB : begin
        if (!cpu_cs) cpu_sm_state <= CPU_SM_IDLE;
        else wb_en <= 1'b1;
      end
      CPU_SM_READ : begin
        // on hit update LRU flag in tag memory
        if (cc_en && itag0_match && itag0_valid) begin
          // data is already in instruction cache way 0
          cpu_dat_r <= idram0_cpu_dat_r;
          cpu_ack <= 1'b1;
          cpu_sm_itag_we <= 1'b1;
          cpu_sm_tag_dat_w <= {1'b0, itram_cpu_dat_r[38:0]};
          cpu_sm_state <= CPU_SM_WAIT;
        end else if (cc_en && itag1_match && itag1_valid) begin
          // data is already in instruction cache way 1
          cpu_dat_r <= idram1_cpu_dat_r;
          cpu_ack <= 1'b1;
          cpu_sm_itag_we <= 1'b1;
          cpu_sm_tag_dat_w <= {1'b1, itram_cpu_dat_r[38:0]};
          cpu_sm_state <= CPU_SM_WAIT;
        end else if (cc_en && dtag0_match && dtag0_valid) begin
          // data is already in data cache way 0
          cpu_dat_r <= ddram0_cpu_dat_r;
          cpu_ack <= 1'b1;
          cpu_sm_dtag_we <= 1'b1;
          cpu_sm_tag_dat_w <= {1'b0, dtram_cpu_dat_r[38:0]};
          cpu_sm_state <= CPU_SM_WAIT;
        end else if (cc_en && dtag1_match && dtag1_valid) begin
          // data is already in data cache way 1
          cpu_dat_r <= ddram1_cpu_dat_r;
          cpu_ack <= 1'b1;
          cpu_sm_dtag_we <= 1'b1;
          cpu_sm_tag_dat_w <= {1'b1, dtram_cpu_dat_r[38:0]};
          cpu_sm_state <= CPU_SM_WAIT;
        end else begin
          // on miss fetch data from SDRAM
          sdr_read_req <= 1'b1;
          cpu_sm_state <= CPU_SM_FILL1;
        end
      end
      CPU_SM_WAIT : begin
        if (!cpu_cs) cpu_sm_state <= CPU_SM_IDLE;
      end
      CPU_SM_FILL1 : begin
        fill <= 1'b1;
        cpu_sm_adr <= cpu_adr[10:1]; 
        if (!sdr_read_ack) begin
          sdr_read_req <= 1'b1;
        end else begin
          sdr_read_req <= 1'b0;
          // read data to cpu
          cpu_dat_r <= sdr_dat_r;
          cpu_ack <= 1'b1;
          if (cache_inhibit) begin
            // don't update cache if caching is inhibited
            cpu_sm_state <= CPU_SM_FILLW;
          end else begin      
            // update tag ram
            if (cpu_ir) begin
              if (itag_lru) begin
                cpu_sm_tag_dat_w <= {1'b0, 1'b1, itram_cpu_dat_r[37], 1'b0, itram_cpu_dat_r[35:18], cpu_adr_tag};
              end else begin
                cpu_sm_tag_dat_w <= {1'b1, itram_cpu_dat_r[38], 1'b1, 1'b0, cpu_adr_tag, itram_cpu_dat_r[17: 0]};
              end
            end else begin
              if (dtag_lru) begin
                cpu_sm_tag_dat_w <= {1'b0, 1'b1, dtram_cpu_dat_r[37], 1'b0, dtram_cpu_dat_r[35:18], cpu_adr_tag};
              end else begin
                cpu_sm_tag_dat_w <= {1'b1, dtram_cpu_dat_r[38], 1'b1, 1'b0, cpu_adr_tag, dtram_cpu_dat_r[17: 0]};
              end
            end
            cpu_sm_itag_we <=  cpu_ir;
            cpu_sm_dtag_we <= !cpu_ir;
            // cache line fill 1st word
            cpu_sm_id   <= cpu_ir;
            cpu_sm_ilru <= itag_lru;
            cpu_sm_dlru <= dtag_lru;
            cpu_sm_mem_dat_w <= sdr_dat_r;
            cpu_sm_iram0_we <=  itag_lru &&  cpu_ir;
            cpu_sm_iram1_we <= !itag_lru &&  cpu_ir;
            cpu_sm_dram0_we <=  dtag_lru && !cpu_ir;
            cpu_sm_dram1_we <= !dtag_lru && !cpu_ir;
            cpu_sm_state <= CPU_SM_FILL2;
          end
        end
      end
      CPU_SM_FILL2 : begin
        if (sdr_read_ack) begin
			  // cache line fill 2nd word
			  fill <= 1'b1;
			  cpu_sm_adr[1:0] <= cpu_sm_adr[1:0] + 2'b01;
			  cpu_sm_mem_dat_w <= sdr_dat_r;
			  cpu_sm_iram0_we <=  cpu_sm_ilru &&  cpu_sm_id;
			  cpu_sm_iram1_we <= !cpu_sm_ilru &&  cpu_sm_id;
			  cpu_sm_dram0_we <=  cpu_sm_dlru && !cpu_sm_id;
			  cpu_sm_dram1_we <= !cpu_sm_dlru && !cpu_sm_id;
			  cpu_sm_state <= CPU_SM_FILL3;
        end
      end
      CPU_SM_FILL3 : begin
        if (sdr_read_ack) begin
			  // cache line fill 3rd word
			  fill <= 1'b1;
			  cpu_sm_adr[1:0] <= cpu_sm_adr[1:0] + 2'b01;
			  cpu_sm_mem_dat_w <= sdr_dat_r;
			  cpu_sm_iram0_we <=  cpu_sm_ilru &&  cpu_sm_id;
			  cpu_sm_iram1_we <= !cpu_sm_ilru &&  cpu_sm_id;
			  cpu_sm_dram0_we <=  cpu_sm_dlru && !cpu_sm_id;
			  cpu_sm_dram1_we <= !cpu_sm_dlru && !cpu_sm_id;
			  cpu_sm_state <= CPU_SM_FILL4;
        end
      end
      CPU_SM_FILL4 : begin
        if (sdr_read_ack) begin
			  // cache line fill 4th word
			  fill <= 1'b1;
			  cpu_sm_adr[1:0] <= cpu_sm_adr[1:0] + 2'b01;
			  cpu_sm_mem_dat_w <= sdr_dat_r;
			  cpu_sm_iram0_we <=  cpu_sm_ilru &&  cpu_sm_id;
			  cpu_sm_iram1_we <= !cpu_sm_ilru &&  cpu_sm_id;
			  cpu_sm_dram0_we <=  cpu_sm_dlru && !cpu_sm_id;
			  cpu_sm_dram1_we <= !cpu_sm_dlru && !cpu_sm_id;
			  cpu_sm_state <= CPU_SM_FILLW;
			  //if (!cpu_ack) cpu_sm_state <= CPU_SM_IDLE;
        end
      end
      CPU_SM_FILLW : begin
        if (!cpu_ack) begin
          cpu_sm_state <= CPU_SM_IDLE;
        end
      end
    endcase
    // when CPU lowers its request signal, lower ack too
    if (!cpu_cs) cpu_ack <= 1'b0;
  end
end


//// sdram side ////

// sdram side state machine
always @ (posedge clk) begin
  if (rst) begin
    cache_init_done   <= 1'b0;
    sdr_sm_state      <= SDR_SM_INIT0;
    sdr_sm_itag_we    <= 1'b0;
    sdr_sm_dtag_we    <= 1'b0;
    sdr_sm_iram0_we   <= 1'b0;
    sdr_sm_iram1_we   <= 1'b0;
    sdr_sm_dram0_we   <= 1'b0;
    sdr_sm_dram1_we   <= 1'b0;
  end else begin
    // default values
    cache_init_done   <= 1'b1;
    sdr_sm_itag_we    <= 1'b0;
    sdr_sm_dtag_we    <= 1'b0;
    sdr_sm_iram0_we   <= 1'b0;
    sdr_sm_iram1_we   <= 1'b0;
    sdr_sm_dram0_we   <= 1'b0;
    sdr_sm_dram1_we   <= 1'b0;
    // state machine
    case (sdr_sm_state)
      SDR_SM_INIT0 : begin
        // prepare to clear cache
        cache_init_done <= 1'b0;
        sdr_sm_adr <= 10'd0;
        sdr_sm_tag_dat_w <= 40'd0;
        sdr_sm_itag_we <= 1'b1;
        sdr_sm_dtag_we <= 1'b1;
        sdr_sm_state <= SDR_SM_INIT1;
      end
      SDR_SM_INIT1 : begin
        // clear cache
        cache_init_done <= 1'b0;
        sdr_sm_adr <= sdr_sm_adr + 10'd4;
        sdr_sm_itag_we <= 1'b1;
        sdr_sm_dtag_we <= 1'b1;
        if (&sdr_sm_adr[9:2]) begin
          sdr_sm_state <= SDR_SM_IDLE;
        end else begin
          sdr_sm_state <= SDR_SM_INIT1;
        end
      end
      SDR_SM_IDLE : begin
        // wait for action
        cache_init_done <= 1'b1;
        sdr_sm_adr <= snoop_adr[10:1];
        if (cc_clr) begin
          sdr_sm_state <= SDR_SM_INIT0;
        end
        else if (snoop_act) begin
          // chip write happening
          sdr_sm_state <= SDR_SM_WAIT;
        end
      end
      SDR_SM_WAIT : begin
        sdr_sm_state <= SDR_SM_SNOOP;
		end
      SDR_SM_SNOOP : begin
        // update if a matching address is in cache
        sdr_sm_mem_dat_w <= snoop_dat_w;
        sdr_sm_iram0_we <= sdr_itag0_match && sdr_itag0_valid;
        sdr_sm_iram1_we <= sdr_itag1_match && sdr_itag1_valid;
        sdr_sm_dram0_we <= sdr_dtag0_match && sdr_dtag0_valid;
        sdr_sm_dram1_we <= sdr_dtag1_match && sdr_dtag1_valid;
        sdr_sm_state <= SDR_SM_IDLE;
      end
    endcase
  end
end


//// instruction memories ////

// instruction tag ram
assign itram_cpu_adr    = cpu_adr_idx;
assign itram_cpu_we     = cpu_sm_itag_we;
assign itram_cpu_dat_w  = cpu_sm_tag_dat_w;
assign itag0_match      = (cpu_adr_tag == itram_cpu_dat_r[17:0]);
assign itag1_match      = (cpu_adr_tag == itram_cpu_dat_r[35:18]);
assign itag_lru         = itram_cpu_dat_r[39];
assign itag0_valid      = itram_cpu_dat_r[38];
assign itag1_valid      = itram_cpu_dat_r[37];
assign itram_sdr_adr    = sdr_sm_adr[9:2];
assign itram_sdr_we     = sdr_sm_itag_we;
assign itram_sdr_dat_w  = sdr_sm_tag_dat_w;
assign sdr_itag0_match  = (snoop_adr[28:11] == itram_sdr_dat_r[17:0]);
assign sdr_itag1_match  = (snoop_adr[28:11] == itram_sdr_dat_r[35:18]);
assign sdr_itag0_valid  = itram_sdr_dat_r[38];
assign sdr_itag1_valid  = itram_sdr_dat_r[37];

dpram #(8,40) itram (
  .clock      (clk              ),
  .address_a  (itram_cpu_adr    ),
  .wren_a     (itram_cpu_we     ),
  .data_a     (itram_cpu_dat_w  ),
  .q_a        (itram_cpu_dat_r  ),
  .address_b  (itram_sdr_adr    ),
  .wren_b     (itram_sdr_we     ),
  .data_b     (itram_sdr_dat_w  ),
  .q_b        (itram_sdr_dat_r  )
);

// instruction data ram 0
assign idram0_cpu_adr   = fill ? cpu_sm_adr : {cpu_adr_idx, cpu_adr_blk};
assign idram0_cpu_bs    = cpu_sm_bs;
assign idram0_cpu_we    = cpu_sm_iram0_we;
assign idram0_cpu_dat_w = cpu_sm_mem_dat_w;
assign idram0_sdr_adr   = snoop_adr[10:1];
assign idram0_sdr_bs    = snoop_bs;
assign idram0_sdr_we    = sdr_sm_iram0_we;
assign idram0_sdr_dat_w = sdr_sm_mem_dat_w;

dpram_be_1024x16 idram0 (
  .clock      (clk              ),
  .address_a  (idram0_cpu_adr   ),
  .byteena_a  (idram0_cpu_bs    ),
  .wren_a     (idram0_cpu_we    ),
  .data_a     (idram0_cpu_dat_w ),
  .q_a        (idram0_cpu_dat_r ),
  .address_b  (idram0_sdr_adr   ),
  .byteena_b  (idram0_sdr_bs    ),
  .wren_b     (idram0_sdr_we    ),
  .data_b     (idram0_sdr_dat_w ),
  .q_b        (idram0_sdr_dat_r )
);

// instruction data ram 1
assign idram1_cpu_adr   = fill ? cpu_sm_adr : {cpu_adr_idx, cpu_adr_blk};
assign idram1_cpu_bs    = cpu_sm_bs;
assign idram1_cpu_we    = cpu_sm_iram1_we;
assign idram1_cpu_dat_w = cpu_sm_mem_dat_w;
assign idram1_sdr_adr   = snoop_adr[10:1];
assign idram1_sdr_bs    = snoop_bs;
assign idram1_sdr_we    = sdr_sm_iram1_we;
assign idram1_sdr_dat_w = sdr_sm_mem_dat_w;

dpram_be_1024x16 idram1 (
  .clock      (clk              ),
  .address_a  (idram1_cpu_adr   ),
  .byteena_a  (idram1_cpu_bs    ),
  .wren_a     (idram1_cpu_we    ),
  .data_a     (idram1_cpu_dat_w ),
  .q_a        (idram1_cpu_dat_r ),
  .address_b  (idram1_sdr_adr   ),
  .byteena_b  (idram1_sdr_bs    ),
  .wren_b     (idram1_sdr_we    ),
  .data_b     (idram1_sdr_dat_w ),
  .q_b        (idram1_sdr_dat_r )
);


//// data data memories ////

// data tag ram
assign dtram_cpu_adr    = cpu_adr_idx;
assign dtram_cpu_we     = cpu_sm_dtag_we;
assign dtram_cpu_dat_w  = cpu_sm_tag_dat_w;
assign dtag0_match      = (cpu_adr_tag == dtram_cpu_dat_r[17:0]);
assign dtag1_match      = (cpu_adr_tag == dtram_cpu_dat_r[35:18]);
assign dtag_lru         = dtram_cpu_dat_r[39];
assign dtag0_valid      = dtram_cpu_dat_r[38];
assign dtag1_valid      = dtram_cpu_dat_r[37];
assign dtram_sdr_adr    = sdr_sm_adr[9:2];
assign dtram_sdr_we     = sdr_sm_dtag_we;
assign dtram_sdr_dat_w  = sdr_sm_tag_dat_w;
assign sdr_dtag0_match  = (snoop_adr[28:11] == dtram_sdr_dat_r[17:0]);
assign sdr_dtag1_match  = (snoop_adr[28:11] == dtram_sdr_dat_r[35:18]);
assign sdr_dtag0_valid  = dtram_sdr_dat_r[38];
assign sdr_dtag1_valid  = dtram_sdr_dat_r[37];

dpram #(8,40) dtram (
  .clock      (clk              ),
  .address_a  (dtram_cpu_adr    ),
  .wren_a     (dtram_cpu_we     ),
  .data_a     (dtram_cpu_dat_w  ),
  .q_a        (dtram_cpu_dat_r  ),
  .address_b  (dtram_sdr_adr    ),
  .wren_b     (dtram_sdr_we     ),
  .data_b     (dtram_sdr_dat_w  ),
  .q_b        (dtram_sdr_dat_r  )
);

// data data ram 0
assign ddram0_cpu_adr   = fill ? cpu_sm_adr : {cpu_adr_idx, cpu_adr_blk};
assign ddram0_cpu_bs    = cpu_sm_bs;
assign ddram0_cpu_we    = cpu_sm_dram0_we;
assign ddram0_cpu_dat_w = cpu_sm_mem_dat_w;
assign ddram0_sdr_adr   = snoop_adr[10:1];
assign ddram0_sdr_bs    = snoop_bs;
assign ddram0_sdr_we    = sdr_sm_dram0_we;
assign ddram0_sdr_dat_w = sdr_sm_mem_dat_w;

dpram_be_1024x16 ddram0 (
  .clock      (clk              ),
  .address_a  (ddram0_cpu_adr   ),
  .byteena_a  (ddram0_cpu_bs    ),
  .wren_a     (ddram0_cpu_we    ),
  .data_a     (ddram0_cpu_dat_w ),
  .q_a        (ddram0_cpu_dat_r ),
  .address_b  (ddram0_sdr_adr   ),
  .byteena_b  (ddram0_sdr_bs    ),
  .wren_b     (ddram0_sdr_we    ),
  .data_b     (ddram0_sdr_dat_w ),
  .q_b        (ddram0_sdr_dat_r )
);

// data data ram 1
assign ddram1_cpu_adr   = fill ? cpu_sm_adr : {cpu_adr_idx, cpu_adr_blk};
assign ddram1_cpu_bs    = cpu_sm_bs;
assign ddram1_cpu_we    = cpu_sm_dram1_we;
assign ddram1_cpu_dat_w = cpu_sm_mem_dat_w;
assign ddram1_sdr_adr   = snoop_adr[10:1];
assign ddram1_sdr_bs    = snoop_bs;
assign ddram1_sdr_we    = sdr_sm_dram1_we;
assign ddram1_sdr_dat_w = sdr_sm_mem_dat_w;

dpram_be_1024x16 ddram1 (
  .clock      (clk              ),
  .address_a  (ddram1_cpu_adr   ),
  .byteena_a  (ddram1_cpu_bs    ),
  .wren_a     (ddram1_cpu_we    ),
  .data_a     (ddram1_cpu_dat_w ),
  .q_a        (ddram1_cpu_dat_r ),
  .address_b  (ddram1_sdr_adr   ),
  .byteena_b  (ddram1_sdr_bs    ),
  .wren_b     (ddram1_sdr_we    ),
  .data_b     (ddram1_sdr_dat_w ),
  .q_b        (ddram1_sdr_dat_r )
);

endmodule


module dpram_be_1024x16
(
	input         clock,

	input	  [9:0] address_a,
	input	  [1:0] byteena_a,
	input	 [15:0] data_a,
	input         wren_a,
	output [15:0] q_a,

	input	  [9:0] address_b,
	input	  [1:0] byteena_b,
	input	 [15:0] data_b,
	input	        wren_b,
	output [15:0] q_b
);

dpram #(10,8) ram_l
(
	.clock(clock),
	.address_a(address_a),
	.data_a(data_a[7:0]),
	.wren_a(byteena_a[0] & wren_a),
	.q_a(q_a[7:0]),
	.address_b(address_b),
	.data_b(data_b[7:0]),
	.wren_b(byteena_b[0] & wren_b),
	.q_b(q_b[7:0])
);

dpram #(10,8) ram_u
(
	.clock(clock),
	.address_a(address_a),
	.data_a(data_a[15:8]),
	.wren_a(byteena_a[1] & wren_a),
	.q_a(q_a[15:8]),
	.address_b(address_b),
	.data_b(data_b[15:8]),
	.wren_b(byteena_b[1] & wren_b),
	.q_b(q_b[15:8])
);

endmodule
