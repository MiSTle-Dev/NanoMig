// Drive sounds after drivesounds.vhd by Alastair M. Robinson (MinimigAGA-MiST-TC64)

module drive_sounds #(parameter [9:0] DS_BASE = 10'h09E)
(
	input             clk,
	input             rst,
	input       [1:0] volume,
	input       [8:0] drive_snd,
	output reg [15:0] sample_l,
	output reg [15:0] sample_r,

	output reg [28:0] ddr_addr,
	output reg        ddr_rd,
	input             ddr_busy,
	input      [63:0] ddr_dout,
	input             ddr_dout_ready
);

reg  [8:0] ds;
reg        step_d;
always @(posedge clk) begin
	ds     <= drive_snd;
	step_d <= ds[0];
end
wire       reset   = ds[8];
wire [3:0] present = ds[7:4];
wire       motor_x = ds[3];
wire       motor   = ds[2];
wire       step_x  = ds[1];
wire       step    = ds[0] & ~step_d;

reg [26:0] ph = 0;
reg        tick = 0;
always @(posedge clk) begin
	tick <= 0;
	if (ph >= 27'd113456540) begin
		ph   <= ph - 27'd113456540;
		tick <= 1;
	end
	else ph <= ph + 27'd44100;
end

reg [24:0] lfsr = 25'h14B4B4A;
always @(posedge clk) lfsr <= {lfsr[23:0], lfsr[24] ^ lfsr[21]};
wire [3:0] pick = 4'd5 + {2'b00, lfsr[1:0]};

localparam HOLD = 17'd88200;
localparam DEB  = 12'd2205;

reg [11:0] trig = 0, act = 0;
reg [11:0] side = 12'hE00;
reg [16:0] idx[0:11];
reg [63:0] line[0:11];
reg [63:0] line_q;
reg [15:0] smp;
reg  [3:0] v = 0;
reg  [2:0] p = 0;
reg        due = 0;
reg signed [24:0] prod;
reg signed [27:0] acc_l = 0, acc_r = 0;
reg  [7:0] hist = 8'h00;
reg        step_req = 0, step_s = 0, motor_d = 0, motor_xd = 0;
reg  [3:0] known = 0;
reg [11:0] deb = 0;
reg [16:0] hold = HOLD;

wire [3:0] snd = (v > 4'd8) ? v - 4'd7 : v;

reg  [7:0] g;
always @(*) begin
	case (snd)
		0,1,2,3: g = 8'd75;
		4:       g = 8'd80;
		5:       g = 8'd160;
		6:       g = 8'd170;
		7:       g = 8'd165;
		default: g = 8'd161;
	endcase
end

wire [16:0] at  = idx[v];
wire        run = trig[v] | (act[v] & ~(v == 4'd3 & ~motor) & ~(v == 4'd10 & ~motor_x));
wire signed [27:0] mix_l = (volume == 2'd3) ? (acc_l >>> 7) : (volume == 2'd2) ? (acc_l >>> 8) : (acc_l >>> 9);
wire signed [27:0] mix_r = (volume == 2'd3) ? (acc_r >>> 7) : (volume == 2'd2) ? (acc_r >>> 8) : (acc_r >>> 9);
wire signed [27:0] near = prod;
wire signed [27:0] far  = prod >>> 2;
wire  [3:0] ins = present & ~known;
wire  [3:0] ej  = known & ~present;

always @(posedge clk) line_q <= line[v];

always @(posedge clk) begin
	if (ddr_rd & ~ddr_busy) ddr_rd <= 0;

	case (p)
		0: if (due) begin
			due   <= 0;
			acc_l <= 0;
			acc_r <= 0;
			v     <= 0;
			if (|volume) p <= 1;
			else begin
				sample_l <= 0;
				sample_r <= 0;
				act      <= 0;
				trig     <= 0;
			end
		end
		1: if (v == 4'd12) begin
			sample_l <= (mix_l > 28'sd32767) ? 16'h7FFF : (mix_l < -28'sd32768) ? 16'h8000 : mix_l[15:0];
			sample_r <= (mix_r > 28'sd32767) ? 16'h7FFF : (mix_r < -28'sd32768) ? 16'h8000 : mix_r[15:0];
			p <= 0;
		end
		else if (run) begin
			act[v]  <= 1;
			trig[v] <= 0;
			if (trig[v] | ~|at[1:0]) begin
				if (trig[v]) idx[v] <= 0;
				ddr_addr <= {DS_BASE, snd, trig[v] ? 15'd0 : at[16:2]};
				ddr_rd   <= 1;
				p <= 2;
			end
			else p <= 3;
		end
		else begin
			act[v] <= 0;
			v <= v + 1'd1;
		end
		2: if (ddr_dout_ready) begin
			line[v] <= ddr_dout;
			smp <= ddr_dout[{at[1:0], 4'b0000} +: 16];
			p <= 4;
		end
		3: begin
			smp <= line_q[{at[1:0], 4'b0000} +: 16];
			p <= 4;
		end
		4: if (smp == 16'h8000) begin
			if (snd == 4'd3 & |at) begin
				idx[v]   <= 0;
				ddr_addr <= {DS_BASE, snd, 15'd0};
				ddr_rd   <= 1;
				p <= 2;
			end
			else begin
				act[v] <= 0;
				v <= v + 1'd1;
				p <= 1;
			end
		end
		else begin
			prod   <= $signed(smp) * $signed({1'b0, g});
			idx[v] <= at + 1'd1;
			p <= 5;
		end
		5: begin
			acc_l <= acc_l + (side[v] ? near : far);
			acc_r <= acc_r + (side[v] ? far : near);
			v <= v + 1'd1;
			p <= 1;
		end
	endcase
	if (tick) due <= 1;

	if (step) begin
		step_req <= 1;
		step_s   <= step_x;
	end
	if (step_req & (~act[pick] | (pick != hist[3:0] & pick != hist[7:4]))) begin
		trig[pick] <= 1;
		side[pick] <= step_s;
		hist <= {hist[3:0], pick};
		step_req <= 0;
	end

	motor_d <= motor;
	if (motor & ~motor_d) trig[3:2] <= 2'b11;
	if (~motor & motor_d) trig[4] <= 1;
	motor_xd <= motor_x;
	if (motor_x & ~motor_xd) trig[10:9] <= 2'b11;
	if (~motor_x & motor_xd) trig[11] <= 1;

	if (reset) begin
		hold <= HOLD;
		deb  <= 0;
	end
	else if (tick) begin
		if (|hold) begin
			hold  <= hold - 1'd1;
			known <= present;
		end
		else if (present == known) deb <= 0;
		else if (deb != DEB) deb <= deb + 1'd1;
		else begin
			if (|ins) begin
				trig[0] <= 1;
				side[0] <= ~ins[0];
			end
			if (|ej) begin
				trig[1] <= 1;
				side[1] <= ~ej[0];
			end
			known <= present;
			deb   <= 0;
		end
	end

	if (rst) begin
		p      <= 0;
		ddr_rd <= 0;
		act    <= 0;
	end
end

endmodule
