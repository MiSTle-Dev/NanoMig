/********************************************/
/* toccata_fifo.v                           */
/* Toccata sound playback                   */
/*                                          */
/* 2022-2023, ranzbak@gmail.com             */
/********************************************/

module toccata_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int FIFO_DEPTH = 1024
) (
    input logic clk,
    input logic rst,
    input logic wr_en,
    input logic rd_en,
    input logic [DATA_WIDTH-1:0] data_in,
    output logic full,
    output logic empty,
    output logic half_full,
    output logic half_empty,
    output logic [DATA_WIDTH-1:0] data_out
);

// Internal variables
(* ramstyle = "M10K" *)
logic [DATA_WIDTH-1:0] fifo_array [FIFO_DEPTH-1:0];
// int read_ptr = 0, write_ptr = 0;
logic [$clog2(FIFO_DEPTH): 0] count; // To handle full and empty states
logic [$clog2(FIFO_DEPTH)-1: 0] write_ptr = 0;
logic [$clog2(FIFO_DEPTH)-1: 0] write_ptr_next = 0;
logic [$clog2(FIFO_DEPTH)-1: 0] read_ptr = 0;
logic [$clog2(FIFO_DEPTH)-1: 0] read_ptr_next = 0;

logic [DATA_WIDTH-1:0] output_next;

logic arm_flags;

// Sequential logic for flags.
// To avoid spurious interrupts if reads and writes happen too close together, we "arm"
// the half_* flags when the counter reaches the halfway point, then trigger the
// flag when the counter moves 7 or 8 steps aware from centre.  (Might be able to get away with less)

always_ff @(posedge clk) begin
	if (rst) begin
		arm_flags <= 1'b0;
		half_empty <= 1'b0;
		half_full <= 1'b0;
	end else begin
		half_empty <= 1'b0;
		half_full <= 1'b0;
		if (count==(FIFO_DEPTH/2))  // count[3:0]==4'b0000
			arm_flags <= 1'b1;
		if (count[3:0]==4'b1000) begin // -8
			half_empty <= arm_flags;
			arm_flags <= 1'b0;
		end
		if (count[3:0]==4'b0111) begin // +7
			half_full <= arm_flags;
			arm_flags <= 1'b0;
		end
	end
end

always_comb begin
    // flags
    full = (count == FIFO_DEPTH - 1);
    empty = (count == 0);

    // Next pointer state
    write_ptr_next = write_ptr + 1'd1;
    read_ptr_next = read_ptr + 1'd1;
end


// Sequential logic for read and write operations
always_ff @(posedge clk) begin

    if (rst) begin
        read_ptr <= 0;
        write_ptr <= 0;
        count <= 0;
        data_out <= 0;
        output_next <= 0;
    end else begin
        // Data out
        output_next <= fifo_array[read_ptr];

        // Write to the FIFO
        if (wr_en && !full) begin
            fifo_array[write_ptr] <= data_in;
            write_ptr <= write_ptr_next;
            count <= count + 1'd1;
        end

        // READ from the FIFO
        if (rd_en && !empty) begin
            data_out <= output_next;
            read_ptr <= read_ptr_next; // Move pointer to next position
            count <= count - 1'd1; // One less byte in the FIFO
        end

        // If read and write are both active, count doesn't change: 1 in, 1 out.
        if (rd_en && !empty && wr_en && !full) begin
            count <= count;
        end
    end
end

endmodule
