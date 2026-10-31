`timescale 1ns / 1ps

module toccata_volume_top_tb;

// Test bench signals
logic clk;
logic rst;
logic signed [15:0] audio_in_left, audio_in_right;
logic [5:0] attenuation_left, attenuation_right;
logic signed [15:0] audio_out_left, audio_out_right;

real PI = 3.141592654;

// Counter for tracking clock cycles
int pos_counter;
int cycle_counter;

// Instantiate the Unit Under Test (UUT)
toccata_volume uut (
    .clk(clk),
    .rst(rst),
    .audio_in_left(audio_in_left),
    .audio_in_right(audio_in_right),
    .attenuation_left(attenuation_left),
    .attenuation_right(attenuation_right),
    .audio_out_left(audio_out_left),
    .audio_out_right(audio_out_right)
);


// Reset pulse
initial begin
    clk = 0;
    rst = 1;
    #20 rst = 0;
end

// Clock generation
always #5 clk = ~clk; // 100 MHz clock

wire signed [15:0] audio_in_next;
int        pos_counter_next;

assign audio_in_next = $rtoi($sin(2 * PI * (pos_counter / 64.0)) * 32767);
assign pos_counter_next = pos_counter + 1;

// Sine wave generation and counter increment
always_ff @(posedge clk) begin
    if (rst) begin
        pos_counter <= 0;
        cycle_counter <= 0;
        audio_in_left <= 0;
        audio_in_right <= 0;
        attenuation_left <= 0;
        attenuation_right <= 0;
    end else begin
        pos_counter <= pos_counter_next;
        audio_in_left <= audio_in_next;
        audio_in_right <= audio_in_next;

        // Go through 64 cycles with increasing attenuation
        if (pos_counter == 64) begin
            // Adjust attenuation every 64 cycles (one sine wave period)
            if (attenuation_left < 64) begin
                attenuation_left <= attenuation_left + 1;
                attenuation_right <= attenuation_right + 1;
            end
            cycle_counter <= cycle_counter + 1;
            pos_counter <= 0;
        end else begin
            // Continue with the cycle
            pos_counter <= pos_counter + 1;
        end
        // Finish the simulation
        if (cycle_counter == 'd64) begin
            $finish("Done");
        end
    end
end

endmodule