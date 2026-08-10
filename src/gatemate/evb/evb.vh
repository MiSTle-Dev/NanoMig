`define BOARD_FREQ_STR "10.0"
`define BOARD_FREQ 10000000

`define GATEMATE   1
`define INFER_DPRAM  1 
`define TMDS_BY_LOGIC  1 

(* blackbox *)
module CC_PLL #(
        parameter REF_CLK = "", // e.g. "10.0"
        parameter OUT_CLK = "", // e.g. "50.0"
        parameter PERF_MD = "", // LOWPOWER, ECONOMY, SPEED
        parameter LOCK_REQ = 1,
        parameter CLK270_DOUB = 0,
        parameter CLK180_DOUB = 0,
        parameter LOW_JITTER = 1,
        parameter CI_FILTER_CONST = 2,
        parameter CP_FILTER_CONST = 4
)(
        input  CLK_REF, CLK_FEEDBACK, USR_CLK_REF,
        input  USR_LOCKED_STDY_RST,
        output USR_PLL_LOCKED_STDY, USR_PLL_LOCKED,
        output CLK270, CLK180, CLK90, CLK0, CLK_REF_OUT
);
endmodule

(* blackbox *)
module CC_LVDS_OBUF #(
	parameter PIN_NAME_P = "UNPLACED",
	parameter PIN_NAME_N = "UNPLACED",
	parameter V_IO = "UNDEFINED",
	parameter [0:0] LVDS_BOOST = 1'bx,
	// IOSEL
	parameter [3:0] DELAY_OBF = 1'bx,
	parameter [0:0] FF_OBF = 1'bx
)(
	input  A,
	(* iopad_external_pin *)
	output O_P, O_N
);
	assign O_P = A;
	assign O_N = ~A;

endmodule


