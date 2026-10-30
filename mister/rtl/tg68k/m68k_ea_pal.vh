always @* case(ea_i)
	5'd0: ea_e = 16'h0000;
	5'd1: ea_e = 16'h8000;
	5'd2: ea_e = 16'h8200;
	5'd3: ea_e = 16'h8210;
	5'd4: ea_e = 16'h8211;
	5'd5: ea_e = 16'h8302;
	5'd6: ea_e = 16'h830A;
	5'd7: ea_e = 16'h8408;
	5'd8: ea_e = 16'h8410;
	5'd9: ea_e = 16'h8414;
	5'd10: ea_e = 16'h8420;
	5'd11: ea_e = 16'h8421;
	5'd12: ea_e = 16'h8512;
	5'd13: ea_e = 16'h8618;
	5'd14: ea_e = 16'h8620;
	5'd15: ea_e = 16'h8624;
	5'd16: ea_e = 16'h8631;
	5'd17: ea_e = 16'h8722;
	5'd18: ea_e = 16'h8828;
	5'd19: ea_e = 16'h8834;
	5'd20: ea_e = 16'h8841;
	5'd21: ea_e = 16'h8A44;
	default: ea_e = 16'd0;
endcase
